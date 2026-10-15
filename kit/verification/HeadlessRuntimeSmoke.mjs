import {createServer} from 'node:http'
import {spawn} from 'node:child_process'
import {mkdir,writeFile,readFile} from 'node:fs/promises'
import path from 'node:path'
import assert from 'node:assert/strict'
const root='C:\\DSH',run=path.join(root,'logs','headless-runtime-'+Date.now()),workspace=path.join(root,'workspace'),home=path.join(root,'data','headless-home')
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
const argv=[path.join(root,'source','deepseek-harness-master','node_modules','@deepseek-ai','dsh','lib','bin.js'),'--profile','headless','Use write to create CANARY.txt and read to verify it.']
let stdout='',stderr=''
const child=spawn(node,argv,{cwd:workspace,env,stdio:['ignore','pipe','pipe'],windowsHide:true})
child.stdout.on('data',c=>stdout+=c);child.stderr.on('data',c=>stderr+=c)
let timedOut=false
const timeout=setTimeout(()=>{timedOut=true;child.kill()},90000)
let code,failure
try{
  code=await new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',resolve)})
  assert.equal(timedOut,false);assert.equal(code,0,stderr)
  assert.equal(await readFile(path.join(workspace,'CANARY.txt'),'utf8'),marker)
  assert.equal(requests.length,3)
  assert.equal(requests[0].reasoning_effort,'none')
  assert.ok(requests[1].messages.some(m=>m.role==='tool'))
  assert.ok(requests[2].messages.some(m=>m.role==='tool'&&JSON.stringify(m).includes(marker)))
  assert.match(stdout,new RegExp(marker))
  console.log('PASS: full Windows headless profile executed write/read with local model route')
}catch(e){failure={message:e.message,stack:e.stack};process.exitCode=1}finally{
  clearTimeout(timeout);server.closeAllConnections();await new Promise(resolve=>server.close(resolve))
  await writeFile(path.join(run,'stdout.log'),stdout);await writeFile(path.join(run,'stderr.log'),stderr)
  await writeFile(path.join(run,'requests.json'),JSON.stringify(requests,null,2))
  await writeFile(path.join(run,'result.json'),JSON.stringify({passed:!failure,error:failure,code,timedOut,argv,requests:requests.length,scope:'full Windows headless profile and filesystem; deterministic local model API'},null,2))
  await writeFile(path.join(root,'logs/latest-headless-runtime-test.json'),JSON.stringify({run,passed:!failure,error:failure},null,2));console.log('Evidence:',run)
}
