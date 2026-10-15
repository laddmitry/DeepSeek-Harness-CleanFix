import {createServer} from 'node:http'
import {spawn} from 'node:child_process'
import {mkdir,writeFile,readFile} from 'node:fs/promises'
import path from 'node:path'
import assert from 'node:assert/strict'
const root='C:\\DSH',run=path.join(root,'logs','acp-runtime-'+Date.now()),workspace=path.join(root,'workspace'),home=path.join(root,'data','acp-home')
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
const argv=[path.join(root,'source','deepseek-harness-master','node_modules','@deepseek-ai','dsh','lib','bin.js'),'--profile','acp']
const child=spawn(node,argv,{cwd:workspace,env,stdio:['pipe','pipe','pipe'],windowsHide:true})
const pending=new Map(),frames=[]
let serial=0,buffer='',stderr=''
const exited=new Promise(resolve=>child.on('exit',(code,signal)=>resolve({code,signal})))
child.stderr.on('data',c=>stderr+=c)
child.stdout.setEncoding('utf8')
child.stdout.on('data',chunk=>{
  buffer+=chunk
  for(;;){
    const i=buffer.indexOf('\n');if(i<0)break
    const line=buffer.slice(0,i);buffer=buffer.slice(i+1)
    if(!line.trim())continue
    const frame=JSON.parse(line);frames.push(frame)
    if(frame.id!==undefined&&('result' in frame||'error' in frame)){
      const waiter=pending.get(frame.id)
      if(waiter){pending.delete(frame.id);clearTimeout(waiter.timer);frame.error?waiter.reject(new Error(JSON.stringify(frame.error))):waiter.resolve(frame.result)}
    } else if(frame.id!==undefined&&frame.method){
      child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:frame.id,error:{code:-32601,message:'No client filesystem or execution capability in this fixture'}})+'\n')
    }
  }
})
function rpc(method,params){
  const id=++serial
  return new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>{pending.delete(id);reject(new Error('ACP timeout: '+method+'; '+stderr))},30000)
    pending.set(id,{resolve,reject,timer})
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n')
  })
}
let failure
try{
  const initialized=await rpc('initialize',{protocolVersion:1,clientCapabilities:{}})
  assert.equal(initialized.protocolVersion,1)
  const session=await rpc('session/new',{cwd:workspace,mcpServers:[]})
  const result=await rpc('session/prompt',{sessionId:session.sessionId,prompt:[{type:'text',text:'Use write to create CANARY.txt and read to verify it.'}]})
  assert.equal(result.stopReason,'end_turn')
  assert.equal(await readFile(path.join(workspace,'CANARY.txt'),'utf8'),marker)
  assert.equal(requests.length,3)
  assert.equal(requests[0].reasoning_effort,'none')
  assert.ok(requests[2].messages.some(m=>m.role==='tool'&&JSON.stringify(m).includes(marker)))
  await rpc('session/close',{sessionId:session.sessionId})
  console.log('PASS: packaged ACP profile initialized, created a session, and used write/read through the local model route')
}catch(e){failure={message:e.message,stack:e.stack};process.exitCode=1}finally{
  child.stdin.end()
  const timer=setTimeout(()=>child.kill(),6000)
  const exit=await exited;clearTimeout(timer)
  for(const waiter of pending.values()){clearTimeout(waiter.timer);waiter.reject(new Error('ACP process closed'))}
  server.closeAllConnections();await new Promise(resolve=>server.close(resolve))
  await writeFile(path.join(run,'requests.json'),JSON.stringify(requests,null,2))
  await writeFile(path.join(run,'frames.json'),JSON.stringify(frames,null,2))
  await writeFile(path.join(run,'stderr.log'),stderr)
  await writeFile(path.join(run,'exit.json'),JSON.stringify(exit,null,2))
  await writeFile(path.join(run,'result.json'),JSON.stringify({passed:!failure,error:failure,exit},null,2));
  await writeFile(path.join(root,'logs/latest-acp-runtime-test.json'),JSON.stringify({run,passed:!failure,error:failure},null,2));
  console.log('Evidence:',run)
}
