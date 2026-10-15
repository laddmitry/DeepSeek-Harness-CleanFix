// Source composition check; network and model behavior have separate runtime checks.
import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'
import yaml from 'js-yaml'
const root = new URL('../', import.meta.url)
const schema = yaml.DEFAULT_SCHEMA.extend([new yaml.Type('tag:yaml.org,2002:js', {
  kind: 'scalar', construct: value => value,
})])
const text = await readFile(new URL('packages/bundle/base/cordis.patch.yml', root), 'utf8')
const [base] = yaml.load(text, { schema })
const rows = new Map(base.insert.map(row => [row.id, row]))
for (const id of ['deepseek-llm-api-extensions', 'session-log-deepseek', 'plugin-package-inventory-deepseek',
  'deepseek-account', 'web-search-deepseek', 'llm-deepseek', 'llm-deepseek-account']) {
  assert.equal(rows.get(id)?.disabled, true, id)
}
for (const id of ['session-persistence-jsonl', 'tool-fs', 'tool-fs-search', 'subagent', 'settings', 'permission',
  'agent-instructions', 'skill-filesystem', 'tool-skill']) {
  assert.ok(rows.has(id), id)
  assert.notEqual(rows.get(id).disabled, true, id)
}
assert.match(rows.get('llm-pi-ai').config.providers['local-offline'].baseURL, /127\.0\.0\.1:11434\/v1/)
assert.equal(rows.get('agent-default-model').config.provider, 'local-offline')
const acp = yaml.load(await readFile(new URL('packages/bundle/acp-app/cordis.patch.yml', root), 'utf8'), { schema })
const bridge = acp.flatMap(patch => patch.insert ?? []).find(row => row.id === 'acp')
assert.equal(bridge.config.provider, 'local-offline')
assert.match(bridge.config.model, /DSH_LOCAL_MODEL_NAME/)
console.log('PASS: DeepSeek rows disabled; local tools and persistence enabled in base source')
