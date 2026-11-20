// Real locked Host/RPC for missing and invalid presets; controlled controller
// dependencies separately protect the existing catch-priority boundaries.
import assert from 'node:assert/strict';
import { before, after, test } from 'node:test';
import { createServer } from 'node:http';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

if (!process.env.DSH_PREFIX) throw new Error('Set DSH_PREFIX to a private fully patched locked prefix');
const prefix = resolve(process.env.DSH_PREFIX);
let root, child, exited, watchdog, model, base, cookie;
let hostText = '', modelRequests = 0, requestId = 0, expectLiveTurn = false;
const liveTurnResponse = Promise.withResolvers();
const clean = text => text.replace(/token=[\w-]+/g, 'token=[REDACTED]');
const load = name => import(pathToFileURL(join(prefix, 'node_modules/@deepseek-ai', name, 'lib/index.js')));

before(async () => {
  root = await mkdtemp(join(tmpdir(), 'preset-resume-errors-'));
  const profileRoot = join(root, 'profile'), workspace = join(root, 'workspace'), sessions = join(root, 'sessions');
  await mkdir(profileRoot); await mkdir(workspace);
  const { Context } = await load('cordis'), { SessionStore } = await load('dsh-session');
  const Jsonl = await load('dsh-session-persistence-jsonl'), { createUserMessage } = await load('dsh-llm');
  const ctx = new Context();
  try {
    await ctx.plugin(SessionStore);
    await ctx.plugin(Jsonl, { root: sessions, compression: 'none' });
    for (const [id, preset] of [['missing', 'synthetic-removed'], ['invalid', 'synthetic-invalid'], ['valid', undefined]]) {
      const session = ctx.sessions.create(`synthetic-${id}`, { meta: { cwd: workspace } });
      if (preset) session.append('agent-preset/selected', { agentPreset: preset });
      session.append('turn/start', { turn: 1 });
      session.append('user/message', createUserMessage({
        content: [{ type: 'text', text: 'Synthetic retained history' }],
        source: { kind: 'user', rpcId: `synthetic-${id}` },
      }), { surfaceOp: 'append' });
      session.append('turn/end', { turn: 1, reason: { kind: 'completed' } });
      const writer = await ctx.sessionPersistence.create(session.header);
      try { await writer.append(session.snapshotEvents()); await writer.flush(); }
      finally { await writer.close(); }
    }
  } finally { await ctx.fiber.dispose(); }
  model = createServer((req, res) => {
    modelRequests++;
    req.resume();
    if (!expectLiveTurn || req.url !== '/v1/messages') {
      res.writeHead(500); res.end('Unexpected synthetic model request'); return;
    }
    expectLiveTurn = false;
    liveTurnResponse.resolve(res);
  });
  model.listen(0, '127.0.0.1'); await once(model, 'listening');
  const invalidPlugin = join(root, 'invalid-preset.mjs');
  await writeFile(invalidPlugin, "export function apply() { throw new Error('Synthetic invalid preset definition'); }\n");
  const patch = ['session-title-llm', 'llm-pi-ai', 'llm-deepseek-account', 'session-telemetry-otel',
    'desktop-product-telemetry', 'web-search-deepseek', 'web-deepseek-api', 'web-fetch-http', 'tool-web']
    .map(id => ({ id, disabled: true }));
  patch.push(
    { id: 'llm-deepseek', config: { baseURL: `http://127.0.0.1:${model.address().port}/v1`, apiKeyEnv: 'SYNTHETIC_UNUSED_KEY' } },
    { id: 'agent-default-model', config: { provider: 'deepseek-official', model: 'deepseek-flash' } },
    { id: 'session-persistence-jsonl', config: { root: sessions, compression: 'none' } },
    { id: 'fs-sandbox', config: { cwd: workspace } },
    { insert: [
      { id: 'synthetic-invalid-preset', name: '@deepseek-ai/dsh-agent-preset', config: {
        id: 'synthetic-invalid', plugins: [{ id: 'synthetic-invalid-entry', name: pathToFileURL(invalidPlugin).href }],
      } },
      { id: 'synthetic-resume-controls', name: new URL('./fixtures/preset-resume-controls.mjs', import.meta.url).href },
    ] },
  );
  const patchPath = join(root, 'patch.json'); await writeFile(patchPath, JSON.stringify(patch));
  const inherited = Object.fromEntries(['PATH', 'LANG', 'LC_ALL', 'TMPDIR'].filter(k => process.env[k]).map(k => [k, process.env[k]]));
  child = spawn(process.execPath, [join(prefix, 'node_modules/@deepseek-ai/dsh/lib/bin.js'), 'web', '--patch', patchPath,
    '--host', '127.0.0.1', '--port', '0', '--no-open'], {
    cwd: workspace, env: { ...inherited, DSH_PREFIX: prefix, DSH_HOME: profileRoot,
      DSH_TELEMETRY_DISABLED: '1', SYNTHETIC_UNUSED_KEY: 'synthetic-unused', CI: 'true' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  exited = once(child, 'close');
  const ready = Promise.withResolvers();
  const receive = chunk => {
    hostText += chunk;
    const found = hostText.match(/http:\/\/127\.0\.0\.1:\d+\/\?token=[\w-]+/);
    if (found) ready.resolve(found[0]);
  };
  child.stdout.on('data', receive); child.stderr.on('data', receive);
  watchdog = setTimeout(() => child.kill('SIGKILL'), 45000);
  const launch = await Promise.race([ready.promise, exited.then(() => { throw Error('Private Host exited before ready: ' + clean(hostText)); })]);
  base = new URL(launch).origin;
  const login = await fetch(launch, { redirect: 'manual', signal: AbortSignal.timeout(10000) });
  cookie = login.headers.getSetCookie().map(value => value.split(';', 1)[0]).join('; ');
  assert(cookie, 'Expected authenticated local Host cookie');
}, { timeout: 45000 });

after(async () => {
  if (child) { child.kill('SIGTERM'); await exited; }
  clearTimeout(watchdog);
  if (process.env.DSH_EVIDENCE_DIR) {
    await mkdir(process.env.DSH_EVIDENCE_DIR, { recursive: true });
    await writeFile(join(process.env.DSH_EVIDENCE_DIR, 'host.log'), clean(hostText));
  }
  if (model) { model.closeAllConnections(); await new Promise(done => model.close(done)); }
  if (root) await rm(root, { recursive: true, force: true });
  assert.equal(modelRequests, 1, 'Only the explicit live-turn prompt calls the loopback model');
});

async function rpc(method, args) {
  const response = await fetch(base + '/api/' + method, {
    method: 'POST', headers: { 'content-type': 'application/json', origin: base, cookie },
    body: JSON.stringify({ type: 'client-request', rpcId: String(requestId++), method, payload: { args } }),
    signal: AbortSignal.timeout(10000),
  });
  assert.equal(response.status, 200);
  return (await response.json()).result;
}
const rename = id => rpc('session/rename', { request: { sessionId: id, title: 'Synthetic rename' } });

test('missing preset resume preserves its declared code and details across RPC', async () => {
  const result = await rename('synthetic-missing');
  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'agent-preset/not-found');
  assert.equal(result.error.details.agentPreset, 'synthetic-removed');
  assert(Array.isArray(result.error.details.available));
  assert(!result.error.details.available.includes('synthetic-removed'));
});
test('invalid preset resume preserves its declared code and diagnostic across RPC', async () => {
  const result = await rename('synthetic-invalid');
  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'agent-preset/invalid');
  assert.equal(result.error.details.agentPreset, 'synthetic-invalid');
  assert.match(result.error.details.reason, /Synthetic invalid preset definition/);
});
test('rejected resumes keep both histories listed and readable without changing their presets', async () => {
  for (const id of ['missing', 'invalid']) {
    assert.equal((await rename(`synthetic-${id}`)).ok, false);
    const list = await rpc('session/list', { _request: {} }); assert.equal(list.ok, true);
    const row = list.value.items.find(item => item.sessionId === `synthetic-${id}`);
    assert(row); assert.equal(row.blank, false); assert.equal(row.agentAvailable, false);
    assert.deepEqual(row.projections.values.sessionListMetadata.lastTurnOutcome, {
      turn: 1, reason: { kind: 'completed' },
    });
    const projected = await rpc('session/projections', { request: { sessionId: `synthetic-${id}` } });
    assert.equal(projected.ok, true);
    assert.equal(projected.value.values.agentPreset, id === 'missing' ? 'synthetic-removed' : 'synthetic-invalid');
  }
});
test('a valid cold session still resumes, while a missing session stays not-found', async () => {
  assert.equal((await rename('synthetic-valid')).ok, true);
  const absent = await rename('synthetic-absent');
  assert.equal(absent.ok, false); assert.equal(absent.error.code, 'session/not-found');
});
test('a live next turn clears the prior outcome until its terminal event', { timeout: 15000 }, async () => {
  const sessionId = 'synthetic-valid';
  async function row() {
    const list = await rpc('session/list', { _request: {} });
    assert.equal(list.ok, true);
    return list.value.items.find(item => item.sessionId === sessionId);
  }
  assert.equal(modelRequests, 0, 'Resolving presets did not call the model');
  assert.deepEqual((await row()).projections.values.sessionListMetadata.lastTurnOutcome, {
    turn: 1, reason: { kind: 'completed' },
  });
  expectLiveTurn = true;
  const receipt = await rpc('session/prompt', { request: {
    sessionId, requestId: 'synthetic-next-turn', mode: 'queue',
    content: [{ type: 'text', text: 'Synthetic next turn' }],
  } });
  assert.equal(receipt.value?.accepted, true, JSON.stringify(receipt));
  const response = await liveTurnResponse.promise;
  try {
    const running = await row();
    assert.equal(running.running, true);
    assert(!Object.hasOwn(running.projections.values.sessionListMetadata, 'lastTurnOutcome'));
  } finally {
    const frames = [
      { type: 'message_start', message: { id: 'synthetic-live', type: 'message', role: 'assistant',
        model: 'deepseek-flash', content: [], usage: { input_tokens: 1, output_tokens: 0 } } },
      { type: 'content_block_start', index: 0, content_block: { type: 'text', text: 'Finished.' } },
      { type: 'content_block_stop', index: 0 },
      { type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 1 } },
      { type: 'message_stop' },
    ];
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.end(frames.map(frame => `event: ${frame.type}\ndata: ${JSON.stringify(frame)}\n\n`).join(''));
  }
  const wait = await rpc('session/wait', { request: { sessionId, timeoutMs: 5000 } });
  assert.equal(wait.value?.reason, 'idle', JSON.stringify(wait));
  const idle = await row();
  assert.equal(idle.running, false);
  assert.deepEqual(idle.projections.values.sessionListMetadata.lastTurnOutcome, {
    turn: 2, reason: { kind: 'completed' },
  });
});
for (const [mode, code] of [
  ['generic', 'gateway/internal'], ['unrelated', 'gateway/internal'], ['foreign', 'agent-preset/not-found'],
  ['writer', 'session/writer-held'], ['live', null], ['subagent', 'session/agent-busy'],
]) {
  test(`controlled ${mode} outcome keeps its error or ownership precedence`, async () => {
    const response = await fetch(base + '/synthetic-preset-resume-controls?mode=' + mode,
      { headers: { cookie }, signal: AbortSignal.timeout(10000) });
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.equal(result.code, code); assert.equal(result.calls, 1);
    if (mode === 'foreign') {
      assert.equal(result.separateBundleClass, true);
      assert.deepEqual(result.details, { agentPreset: 'synthetic-removed', available: ['standard'] });
    }
    if (mode === 'generic' || mode === 'unrelated') assert.deepEqual(result.details, {});
    if (mode === 'live') assert.equal(result.agentMatches, true);
    if (mode === 'subagent') assert.match(result.details.reason, /subagent/);
  });
}
