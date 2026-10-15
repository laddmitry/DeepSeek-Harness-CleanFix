import {createServer} from 'node:http'
import {mkdir,writeFile,readFile} from 'node:fs/promises'
import {pathToFileURL} from 'node:url'
import path from 'node:path'
import assert from 'node:assert/strict'
const root='C:\\DSH', workspace=path.join(root,'workspace'), run=path.join(root,'logs','full-runtime-'+Date.now())
await mkdir(run)
const {DeepSeekHarness}=await import(pathToFileURL(path.join(root,'source/deepseek-harness-master/node_modules/@deepseek-ai/dsh-sdk-client/lib/index.js')).href)
const marker='WORKER_SEARCH_'+Date.now(),file=marker+'.txt',requests=[]
const steps=[['write',{file_path:file,content:marker}],['read',{file_path:file}],['glob',{pattern:file,path:workspace}],['grep',{pattern:marker,path:workspace,include:file}]]
const server=createServer((req,res)=>{let data='';req.on('data',c=>data+=c);req.on('end',()=>{
 try{
 const body=JSON.parse(data);requests.push(body);const n=requests.length,step=steps[n-1]
 const delta=step?{role:'assistant',tool_calls:[{index:0,id:'call_'+n,type:'function',function:{name:step[0],arguments:JSON.stringify(step[1])}}]}:{role:'assistant',content:marker}
 const base={id:'mock-'+n,object:'chat.completion.chunk',created:1,model:'qwen3:0.6b'}
 res.writeHead(200,{'content-type':'text/event-stream'})
 res.write('data: '+JSON.stringify({...base,choices:[{index:0,delta,finish_reason:null}]})+'\n\n')
 res.write('data: '+JSON.stringify({...base,choices:[{index:0,delta:{},finish_reason:step?'tool_calls':'stop'}],usage:{prompt_tokens:100,completion_tokens:20,total_tokens:120}})+'\n\n')
 res.end('data: [DONE]\n\n')
 }catch(e){res.writeHead(500);res.end(e.message)}
})})
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve))
const env={...process.env,DSH_HOME:path.join(root,'data/home'),DSH_AGENTS_HOME:path.join(workspace,'.agents'),DSH_LOCAL_MODEL_BASE_URL:`http://127.0.0.1:${server.address().port}/v1`,DSH_LOCAL_MODEL_NAME:'qwen3:0.6b',DSH_WORKER_CREDENTIAL_FILE:path.join(root,'data/worker-credentials.json'),DSH_NETWORK_LOG:path.join(run,'network.jsonl')}
if(env.NODE_OPTIONS)throw Error('Unexpected NODE_OPTIONS')
const client=new DeepSeekHarness({dshBin:path.join(root,'source/deepseek-harness-master/node_modules/@deepseek-ai/dsh/lib/bin.js'),cwd:workspace,processCwd:workspace,dshHome:env.DSH_HOME,env,initializeTimeoutMs:60000,requestTimeoutMs:60000})
let result,error,timer
try{
 result=await Promise.race([client.run('Create the canary, read it, then find its path and text using glob and grep.'),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Full runtime test exceeded 150 seconds')),150000)})])
 assert.equal((await readFile(path.join(workspace,file),'utf8')).trim(),marker)
 const calls=result.events.filter(e=>e.type==='tool/call')
 for(const name of ['write','read','glob','grep']){
  const ids=new Set(calls.filter(e=>e.data.name===name).map(e=>e.data.callId))
  assert.ok(ids.size,'Missing call: '+name)
  assert.ok(result.events.some(e=>e.type==='tool/result'&&ids.has(e.data.message.toolCallId)&&!e.data.message.isError&&JSON.stringify(e.data.message.content).includes(name==='glob'?file: name==='write'?'':marker)),'No successful nonempty result: '+name)
 }
 const names=requests[0].tools.map(t=>t.function.name)
 for(const forbidden of ['bash','pwsh','web_search','web_fetch'])assert.ok(!names.includes(forbidden),'Unexpected tool '+forbidden)
 assert.equal(requests.length,5)
 console.log('PASS: full Windows configuration executed write/read/glob/grep without a fixture overlay')
}catch(e){error={message:e.message,stack:e.stack};process.exitCode=1}
finally{
 clearTimeout(timer);await client.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve))
 await writeFile(path.join(run,'result.json'),JSON.stringify({passed:!error,error,file,marker,result,scope:'real Windows worker and file search; deterministic model API'},null,2))
 await writeFile(path.join(run,'requests.json'),JSON.stringify(requests,null,2))
 await writeFile(path.join(root,'logs/latest-full-runtime-test.json'),JSON.stringify({run,passed:!error,error},null,2))
 console.log('Evidence:',run)
}
