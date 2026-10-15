import {mkdir,writeFile,readFile} from 'node:fs/promises'
import {pathToFileURL} from 'node:url'
import {randomUUID} from 'node:crypto'
import path from 'node:path'
import assert from 'node:assert/strict'
const root='C:\\DSH',workspace=path.join(root,'workspace')
const run=path.join(root,'logs','real-model-'+Date.now())
await mkdir(run)
const {DeepSeekHarness}=await import(pathToFileURL(path.join(root,'source','deepseek-harness-master','node_modules','@deepseek-ai','dsh-sdk-client','lib','index.js')).href)
const marker='HARNESS_REAL_LOCAL_'+randomUUID().replaceAll('-','')
const file='MODEL_CANARY_'+Date.now()+'.txt'
const env={...process.env,DSH_HOME:path.join(root,'data','home'),DSH_AGENTS_HOME:path.join(workspace,'.agents'),
 DSH_LOCAL_MODEL_BASE_URL:'http://127.0.0.1:11434/v1',DSH_LOCAL_MODEL_NAME:'qwen3:0.6b',
 DSH_LOCAL_MODEL_CONTEXT_WINDOW:'8192',DSH_LOCAL_MODEL_MAX_TOKENS:'2048',DSH_TELEMETRY_DISABLED:'1',
 DSH_WORKER_CREDENTIAL_FILE:path.join(root,'data','worker-credentials.json'),DSH_NETWORK_LOG:path.join(run,'network.jsonl')}
if(env.NODE_OPTIONS)throw new Error('Unexpected NODE_OPTIONS')
const client=new DeepSeekHarness({dshBin:path.join(root,'source','deepseek-harness-master','node_modules','@deepseek-ai','dsh','lib','bin.js'),
 processCwd:workspace,cwd:workspace,dshHome:env.DSH_HOME,env,initializeTimeoutMs:60000,requestTimeoutMs:60000})
let result,error,timer
try{
 result=await Promise.race([
   client.run(`Use the write tool to create a new file ${file} containing exactly ${marker}. Then use the read tool to verify its contents. Do not use shell. After the successful read reply with ${marker}.`),
   new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Real model activity exceeded 600 seconds')),600000)})
 ])
 assert.equal((await readFile(path.join(workspace,file),'utf8')).trim(),marker)
 const calls=result.events.filter(e=>e.type==='tool/call')
 const reads=new Set(calls.filter(e=>e.data.name==='read').map(e=>e.data.callId))
 assert.ok(calls.some(e=>e.data.name==='write'),'No actual write call')
 assert.ok(result.events.some(e=>e.type==='tool/result'&&!e.data.message.isError&&reads.has(e.data.message.toolCallId)&&JSON.stringify(e.data.message.content).includes(marker)),'No successful read result containing the file marker')
 console.log('PASS: real local model executed write/read with a matching file and recorded tool results')
}catch(e){error={message:e.message,stack:e.stack};process.exitCode=1}
finally{
 clearTimeout(timer);await client.close()
 await writeFile(path.join(run,'result.json'),JSON.stringify({passed:!error,marker,file,error,result,scope:'actual Windows worker composition and Ollama; no fixture overlay'},null,2))
 await writeFile(path.join(root,'logs','latest-real-model-test.json'),JSON.stringify({run,passed:!error,error},null,2))
 console.log('Evidence:',run)
}
