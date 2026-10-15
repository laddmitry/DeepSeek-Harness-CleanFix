import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createServer, get } from 'node:http'
import { connect } from 'node:net'
import { resolveLocalModelEndpoint, installLocalNetworkPolicy } from '../apps/cli/src/local-network.ts'

test('model endpoints require literal loopback or private addresses', () => {
  for (const value of ['https://api.deepseek.com/v1', 'http://deepseek.com./v1', 'http://8.8.8.8/v1',
    'http://0.0.0.0/v1', 'http://169.254.169.254/v1', 'http://user:secret@127.0.0.1/v1',
    'ftp://127.0.0.1/v1', 'http://127.0.0.1/v1?target=deepseek.com']) {
    assert.throws(() => resolveLocalModelEndpoint(value))
  }
  assert.equal(resolveLocalModelEndpoint('http://localhost:11434/v1').baseURL, 'http://127.0.0.1:11434/v1')
  assert.equal(resolveLocalModelEndpoint('http://192.168.1.2:8000/v1').host, '192.168.1.2')
  assert.equal(resolveLocalModelEndpoint('http://[::1]:11434/v1').host, '::1')
})

test('HTTP, fetch, normalized TCP overloads and redirects obey the destination restriction', async () => {
  let otherRequests = 0
  const other = createServer((_req, res) => { otherRequests++; res.end('EXTERNAL') })
  const model = createServer((req, res) => {
    if (req.url === '/redirect') {
      res.writeHead(302, { location: `http://127.0.0.1:${other.address().port}/leak` })
      res.end()
    } else res.end('LOCAL_OK')
  })
  await new Promise(resolve => other.listen(0, '127.0.0.1', resolve))
  await new Promise(resolve => model.listen(0, '127.0.0.1', resolve))
  const port = model.address().port
  const release = installLocalNetworkPolicy(resolveLocalModelEndpoint(`http://127.0.0.1:${port}/v1`))
  try {
    assert.equal(await (await fetch(`http://127.0.0.1:${port}/v1/models`)).text(), 'LOCAL_OK')
    const body = await new Promise((resolve, reject) => {
      get(`http://127.0.0.1:${port}/v1/models`, res => {
        let text = ''; res.on('data', chunk => { text += chunk }); res.on('end', () => resolve(text))
      }).on('error', reject)
    })
    assert.equal(body, 'LOCAL_OK')
    assert.throws(() => connect(443, 'api.deepseek.com'), /LOCAL_NETWORK_POLICY/)
    assert.throws(() => connect({ host: '8.8.8.8', port: 443 }), /LOCAL_NETWORK_POLICY/)
    await assert.rejects(fetch('https://api.deepseek.com/v1/models'))
    await assert.rejects(fetch(`http://127.0.0.1:${port}/redirect`))
    assert.equal(otherRequests, 0)
  } finally {
    release()
    model.closeAllConnections(); other.closeAllConnections()
    await Promise.all([new Promise(resolve => model.close(resolve)), new Promise(resolve => other.close(resolve))])
  }
})
