import {createServer} from 'node:http'
import {spawn} from 'node:child_process'
import {mkdir,writeFile,readFile} from 'node:fs/promises'
import path from 'node:path'
import assert from 'node:assert/strict'
const root='C:\\DSH'
const run=path.join(root,'logs','web-runtime-'+Date.now()),workspace=path.join(root,'workspace'),home=path.join(root,'data','web-home')
await mkdir(run);await mkdir(home,{recursive:true})
const requests=[]
const marker='CANARY_HARNESS_MOCK_WRITE_READ_20261015'
const server=createServer((req,res)=>{
  let data='';req.on('data',c=>data+=c);req.on('end',()=>{
    const body=JSON.parse(data);requests.push(body)
    const n=requests.length
    const delta=n===1?{role:'assistant',tool_calls:[{index:0,id:'write_1',type:'function',function:{name:'write',arguments:JSON.stringify({file_path:'CANARY.txt',content:marker})}}]}
      :n===2?{role:'assistant',tool_calls:[{index:0,id:'read_1',type:'function',function:{name:'read',arguments:JSON.stringify({file_path:'CANARY.txt'})}}]}
      :{role:'assistant',content:marker}
    const chunk={id:'local-mock-'+n,object:'chat.completion.chunk',created:1,model:'qwen3:0.6b',choices:[{index:0,delta,finish_reason:null}]}
    res.writeHead(200,{'content-type':'text/event-stream'})
    res.write('data: '+JSON.stringify(chunk)+'\n\n')
    res.write('data: '+JSON.stringify({...chunk,choices:[{index:0,delta:{},finish_reason:n<3?'tool_calls':'stop'}],usage:{prompt_tokens:100,completion_tokens:20,total_tokens:120}})+'\n\n')
    res.end('data: [DONE]\n\n')
  })
})
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve))
const port=server.address().port
const node='C:\\Program Files\\nodejs\\node.exe'
const env={...process.env,DSH_HOME:home,DSH_AGENTS_HOME:path.join(workspace,'.agents'),DSH_WORKER_CREDENTIAL_FILE:path.join(root,'data','worker-credentials.json'),DSH_LOCAL_MODEL_BASE_URL:`http://127.0.0.1:${port}/v1`,DSH_LOCAL_MODEL_NAME:'qwen3:0.6b',DSH_NETWORK_LOG:path.join(run,'network.jsonl'),DSH_TELEMETRY_DISABLED:'1'}
const argv=[path.join(root,'source','deepseek-harness-master','node_modules','@deepseek-ai','dsh','lib','bin.js'),'--profile','web','--no-open','--port','0']
let child=spawn(node,argv,{cwd:workspace,env,stdio:['ignore','pipe','pipe'],windowsHide:true})

let stdout='',stderr='',failure
child.stdout.on('data',c=>stdout+=c);child.stderr.on('data',c=>stderr+=c)
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms))
let rpcCount=0
try{
 let launch
 for(let i=0;i<450;i++){launch=stdout.match(/dsh web: (http:\/\/[^\s]+)/);if(launch)break;if(child.exitCode!==null)throw Error('Web exited before readiness: '+stderr);await wait(100)}
 assert.ok(launch,'No Web readiness URL')
 let url=new URL(launch[1]),origin=url.origin
 const anonymous=await fetch(origin);assert.equal(anonymous.status,401)
 const entry=await fetch(url,{redirect:'manual'});assert.equal(entry.status,303)
 let cookie=entry.headers.get('set-cookie').split(';')[0]
 const index=await fetch(new URL(entry.headers.get('location'),origin),{headers:{cookie}});assert.equal(index.status,200)
 const csp=index.headers.get('content-security-policy');assert.ok(csp.includes("connect-src 'self'"));assert.ok(!csp.includes('unsafe-eval'))
 await writeFile(path.join(run,'index.html'),await index.text())
 async function rpc(method,request){
  const response=await fetch(origin+'/api/'+method,{method:'POST',headers:{'content-type':'application/json',cookie,origin},body:JSON.stringify({type:'client-request',rpcId:'vm-'+(++rpcCount),method,payload:{args:{request}}})})
  const body=await response.json();await writeFile(path.join(run,'rpc-'+rpcCount+'.json'),JSON.stringify({method,status:response.status,body},null,2))
  assert.equal(response.status,200);assert.equal(body.result.ok,true,JSON.stringify(body));return body.result.value
 }
 const created=await rpc('session/create',{cwd:workspace})
 assert.ok(created.sessionId)
 await rpc('session/prompt',{sessionId:created.sessionId,requestId:'web-vm-'+Date.now(),mode:'queue',content:[{type:'text',text:'Create CANARY.txt with the exact marker, then read it.'}]})
 for(let i=0;i<600;i++){try{if((await readFile(path.join(workspace,'CANARY.txt'),'utf8'))===marker&&requests.length>=3)break}catch{}await wait(100)}
 assert.equal(await readFile(path.join(workspace,'CANARY.txt'),'utf8'),marker)
 assert.ok(requests.some(q=>q.messages?.some(m=>m.role==='tool'&&JSON.stringify(m).includes(marker))),'Web turn did not receive read result')
 
 await wait(1000)
 await writeFile(path.join(run,'before-restart.stdout.log'),stdout);await writeFile(path.join(run,'before-restart.stderr.log'),stderr)
 await new Promise(resolve=>{child.once('exit',resolve);child.kill()})
 stdout='';stderr=''
 child=spawn(node,argv,{cwd:workspace,env,stdio:['ignore','pipe','pipe'],windowsHide:true})
 child.stdout.on('data',c=>stdout+=c);child.stderr.on('data',c=>stderr+=c)
 launch=null
 for(let i=0;i<450;i++){launch=stdout.match(/dsh web: (http:\/\/[^\s]+)/);if(launch)break;if(child.exitCode!==null)throw Error('Restarted Web exited: '+stderr);await wait(100)}
 assert.ok(launch,'Restarted Web did not become ready')
 url=new URL(launch[1]);origin=url.origin
 const resumedEntry=await fetch(url,{redirect:'manual'});assert.equal(resumedEntry.status,303)
 cookie=resumedEntry.headers.get('set-cookie').split(';')[0]
 const resumed=await rpc('session/create',{sessionId:created.sessionId,cwd:workspace})
 assert.equal(resumed.sessionId,created.sessionId)
 await rpc('session/prompt',{sessionId:created.sessionId,requestId:'web-resume-'+Date.now(),mode:'queue',content:[{type:'text',text:'Recall the verified file contents.'}]})
 for(let i=0;i<300;i++){if(requests.length>=4)break;await wait(100)}
 assert.ok(requests.length>=4,'Resumed prompt did not reach the local model')
 assert.ok(requests[3].messages.some(m=>m.role==='tool'&&JSON.stringify(m).includes(marker)),'Resumed Web lost the prior read result')
await writeFile(path.join(run,'result.json'),JSON.stringify({passed:true,resumedAfterRestart:true,sessionId:created.sessionId,rpcCount,anonymousStatus:401,tokenExchangeStatus:303,authorizedStatus:200,csp,scope:'Full Web profile via authenticated HTTP API; no browser interaction'},null,2))
 console.log('PASS: token entry, full Web write/read turn and persisted session adoption after process restart')
}catch(e){failure={message:e.message,stack:e.stack};process.exitCode=1;await writeFile(path.join(run,'result.json'),JSON.stringify({passed:false,error:failure},null,2))}
finally{
 child.kill();server.closeAllConnections();await new Promise(resolve=>server.close(resolve))
 await writeFile(path.join(run,'stdout.log'),stdout);await writeFile(path.join(run,'stderr.log'),stderr);await writeFile(path.join(run,'requests.json'),JSON.stringify(requests,null,2))
 await writeFile(path.join(root,'logs/latest-web-runtime-test.json'),JSON.stringify({run,passed:!failure,error:failure},null,2))
 console.log('Evidence:',run)
}
