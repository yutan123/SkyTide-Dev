// Exercises the shipped SDK in isolation; no plugin is installed or bundled.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../assets/plugin_sdk.js'), 'utf8');

function host() {
  const results = new Map(), requests = [];
  const context = vm.createContext({__tideConfig: {token: 'secret'}, sendMessage(channel, raw) {
    const data = JSON.parse(raw);
    if (channel === 'tide.result') results.set(data.id, data);
    else if (channel === 'tide.host') requests.push(data);
    else throw new Error('Unexpected bridge channel');
  }});
  vm.runInContext(source, context);
  let sequence = 0;
  const tick = () => new Promise(resolve => setImmediate(resolve));
  async function call(kind, name, payload) {
    const id = ++sequence;
    context.__tideDispatch(id, kind, name, payload);
    for (let i = 0; i < 100; i++) {
      await tick();
      if (results.has(id)) {
        const result = results.get(id);
        if (result.error) throw new Error(result.error);
        return result.value;
      }
    }
    throw new Error('Unresolved invocation');
  }
  return {context, call, requests, tick, run: code => vm.runInContext(code, context)};
}

test('platform editor uses the dedicated host RPC and returns a denial unchanged', async () => {
  const h = host();
  h.run("tide.registerTool('edit', () => tide.platform.execute('worldBook.update', {robotId: 'b', id: 'w', enabled: false}))");
  const pending = h.call('tool', 'edit', {});
  await h.tick();
  assert.equal(h.context.tide.capabilities.includes('platform.editor'), true);
  assert.equal(h.requests.length, 1);
  const {id, method, args} = h.requests[0];
  assert.equal(method, 'platform.execute');
  assert.deepEqual(args, {
    operation: 'worldBook.update',
    arguments: {robotId: 'b', id: 'w', enabled: false},
  });
  const denied = {ok: false, error: 'cancelled'};
  h.context.__tideResolve(id, denied, null);
  assert.deepEqual(await pending, denied);
});

test('chat read APIs bind to invocation and preserve host validation arguments', async () => {
  const h = host();
  h.run("tide.registerTool('read', async (args, context) => await context.chat.getRecentMessages({limit: args.limit}))");
  const result = h.call('tool', 'read', {__tideInvocation: true, args: {limit: 4}, contextToken: 'read-token'});
  await h.tick();
  assert.equal(h.requests.length, 1);
  assert.equal(h.requests[0].method, 'chat.getRecentMessages');
  assert.equal(h.requests[0].args.contextToken, 'read-token');
  assert.equal(h.requests[0].args.limit, 4);
  h.context.__tideResolve(h.requests[0].id, [{id: 'message'}], null);
  assert.deepEqual(await result, [{id: 'message'}]);
  assert.equal(h.context.tide.capabilities.includes('chat.read'), true);
});

test('message event contexts are scoped and do not leak into later events', async () => {
  const h = host();
  h.run("tide.on('chat.message', async (payload, context) => { await context.chat.getContext(); return payload; })");
  const result = h.call('event', 'chat.message', {__tideEvent: true, contextToken: 'event-token', payload: {botId: 'b1'}});
  await h.tick();
  assert.equal(h.requests[0].args.contextToken, 'event-token');
  h.context.__tideResolve(h.requests[0].id, {botId: 'b1'}, null);
  assert.deepEqual(await result, {botId: 'b1'});
  await assert.rejects(h.call('event', 'chat.message', {botId: 'b2'}), /requires a tool invocation or scoped event context/);
});

test('declarations must match registered tools in both directions', async () => {
  const h = host();
  h.run("tide.registerTool('first', args => args)");
  await h.call('validate', '', ['first']);
  await assert.rejects(h.call('validate', '', ['missing']), /Unregistered/);
  await assert.rejects(h.call('validate', '', []), /Undeclared/);
  assert.throws(() => h.run("tide.registerTool('first', () => null)"), /duplicate/);
});

test('async tool JSON roundtrip and exception isolation', async () => {
  const h = host();
  h.run("tide.registerTool('echo', async args => args); tide.registerTool('bad', () => {throw new Error('broken')})");
  const payload = {text: '引号\'"\\\n ${literal}', array: [false, null, 1]};
  assert.deepEqual(await h.call('tool', 'echo', payload), payload);
  await assert.rejects(h.call('tool', 'bad', {}), /broken/);
  assert.deepEqual(await h.call('tool', 'echo', {alive: true}), {alive: true});
});

test('hook transformations run in registration order and allow takeover', async () => {
  const h = host();
  h.run("tide.on('tool.before', p => ({...p, order: [1]})); tide.on('tool.before', async p => ({...p, order: [...p.order, 2], handled: true, result: {result: {ok: true}}}))");
  const result = await h.call('event', 'tool.before', {call: {}});
  assert.deepEqual(result.order, [1, 2]);
  assert.equal(result.handled, true);
  assert.equal(result.result.result.ok, true);
});

test('storage RPC resolves concurrently and host rejection reaches handler', async () => {
  const h = host();
  h.run("tide.registerTool('read', async () => Promise.all([tide.storage.get('a'), tide.storage.get('b')])); tide.registerTool('write', () => tide.storage.set('a', 7))");
  const read = h.call('tool', 'read', {});
  await h.tick();
  assert.deepEqual(h.requests.map(r => r.args.key), ['a', 'b']);
  h.context.__tideResolve(h.requests[1].id, 'second', null);
  h.context.__tideResolve(h.requests[0].id, 'first', null);
  assert.deepEqual(await read, ['first', 'second']);
  const write = h.call('tool', 'write', {});
  await h.tick();
  h.context.__tideResolve(h.requests[2].id, null, 'permission denied');
  await assert.rejects(write, /permission denied/);
});

test('lifecycle, UI actions and immutable config are available', async () => {
  const h = host();
  h.run("let active = false; tide.on('activate', () => {active = true}); tide.on('deactivate', () => {active = false}); tide.on('ui.action', p => ({ui: {type: 'text', text: p.values.message}, active, token: tide.config.token}))");
  assert.equal(h.run('Object.isFrozen(tide) && Object.isFrozen(tide.config)'), true);
  await h.call('event', 'activate', {});
  assert.equal((await h.call('event', 'ui.action', {values: {message: 'updated'}})).ui.text, 'updated');
  assert.equal((await h.call('event', 'ui.action', {values: {}})).active, true);
  await h.call('event', 'deactivate', {});
  assert.equal((await h.call('event', 'ui.action', {values: {}})).active, false);
});

test('failed RPC serialization releases pending capacity', async () => {
  const h = host();
  h.run("tide.registerTool('failures', async () => {let failures = 0; const x = {}; x.self = x; for (let i = 0; i < 70; i++) {try {await tide.storage.set('x', x)} catch (error) {if (/circular|cyclic/i.test(String(error))) failures++}} return failures}); tide.registerTool('read', () => tide.storage.get('ok'))");
  assert.equal(await h.call('tool', 'failures', {}), 70);
  const read = h.call('tool', 'read', {});
  await h.tick();
  assert.equal(h.requests.length, 1);
  h.context.__tideResolve(h.requests[0].id, 'alive', null);
  assert.equal(await read, 'alive');
});

test('large or cyclic results return errors without hanging callers', async () => {
  const h = host();
  h.run("tide.registerTool('large', () => 'x'.repeat(1048577)); tide.registerTool('cycle', () => {const x = {}; x.x = x; return x})");
  await assert.rejects(h.call('tool', 'large', {}), /exceeds/);
  await assert.rejects(h.call('tool', 'cycle', {}), /circular|cyclic/i);
});

test('storage update preserves expected snapshot and retries competing writes', async () => {
  const h = host();
  h.run("tide.registerTool('increment', () => tide.storage.update('counter', value => {value.count++; return value}))");
  const result = h.call('tool', 'increment', {});
  await h.tick();
  h.context.__tideResolve(h.requests[0].id, {count: 1}, null);
  await h.tick();
  assert.deepEqual(h.requests[1].args, {key: 'counter', expected: {count: 1}, value: {count: 2}});
  h.context.__tideResolve(h.requests[1].id, false, null);
  await h.tick();
  h.context.__tideResolve(h.requests[2].id, {count: 4}, null);
  await h.tick();
  assert.deepEqual(h.requests[3].args, {key: 'counter', expected: {count: 4}, value: {count: 5}});
  h.context.__tideResolve(h.requests[3].id, true, null);
  assert.deepEqual(await result, {count: 5});
});

test('chat capabilities bind concurrent invocations without exposing the token', async () => {
  const h = host();
  h.run(`tide.registerTool('reply', async (args, context) => {
    const info = await tide.chat.getContext(context);
    return context.chat.sendText({text: args.text, requestId: args.key, contextToken: 'forged'});
  })`);
  const first = h.call('tool', 'reply', {__tideInvocation:true,args:{text:'a',key:'a'},contextToken:'token-a'});
  const second = h.call('tool', 'reply', {__tideInvocation:true,args:{text:'b',key:'b'},contextToken:'token-b'});
  await h.tick();
  const contexts = h.requests.splice(0);
  assert.equal(contexts.length,2);
  for (const request of contexts) h.context.__tideResolve(request.id,{botId:request.args.contextToken},null);
  await h.tick();
  const sends = h.requests.splice(0);
  assert.deepEqual(sends.map(r=>[r.args.text,r.args.contextToken]),[['a','token-a'],['b','token-b']]);
  for (const request of sends) h.context.__tideResolve(request.id,{status:'sent',messageId:request.args.requestId},null);
  assert.equal((await first).messageId,'a');
  assert.equal((await second).messageId,'b');
});
test('legacy handler input remains intact and missing context rejects chat APIs', async () => {
  const h = host();
  h.run(`tide.registerTool('legacy', args => args); tide.registerTool('send', (args,ctx)=>ctx.chat.sendText({text:'x',requestId:'x'}))`);
  assert.deepEqual(await h.call('tool','legacy',{hello:'world'}),{hello:'world'});
  await assert.rejects(h.call('tool','send',{}),/requires a tool invocation/);
});
test('workers validate declarations and bind cancellable waits to worker identity', async () => {
  const h = host();
  h.run(`tide.registerWorker('sync', async context => { await context.sleep(25); return context.name; });`);
  await h.call('validateWorkers', '', ['sync']);
  await assert.rejects(h.call('validateWorkers', '', []), /Undeclared/);
  await assert.rejects(h.call('validateWorkers', '', ['missing']), /Unregistered/);
  const result = h.call('worker', 'sync', {workerToken: 'lease-token'});
  await h.tick();
  assert.equal(h.requests[0].method, 'runtime.sleep');
  assert.deepEqual(h.requests[0].args, {ms: 25, workerToken: 'lease-token'});
  h.context.__tideResolve(h.requests[0].id, null, null);
  assert.equal(await result, 'sync');
});
test('command handlers receive scoped chat context and declaration validation', async () => {
  const h = host();
  h.run(`tide.registerCommand('echo', async (args, context) => { await context.chat.sendText({text: args.text, requestId: 'echo-' + args.messageId}); });`);
  await h.call('validateCommands', '', ['echo']);
  await assert.rejects(h.call('validateCommands', '', []), /Undeclared/);
  assert.throws(() => h.run(`tide.registerCommand('echo', () => {});`), /duplicate/);
  const result = h.call('command', 'echo', {args: {text: 'hello', messageId: 'm1'}, contextToken: 'chat-scope'});
  await h.tick();
  assert.equal(h.requests[0].method, 'chat.sendText');
  assert.deepEqual(h.requests[0].args, {text: 'hello', requestId: 'echo-m1', contextToken: 'chat-scope'});
  h.context.__tideResolve(h.requests[0].id, {status: 'sent'}, null);
  assert.equal(await result, null);
});
test('database RPC uses explicit collection and cannot be overridden by options', async () => {
  const h = host();
  h.run(`tide.registerTool('db', () => tide.database.put('safe', 'key', {v: 1}, {collection: 'wrong', key: 'wrong', vector: [1, 0]}));`);
  const result = h.call('tool', 'db', {});
  await h.tick();
  assert.equal(h.requests[0].method, 'database.put');
  assert.deepEqual(h.requests[0].args, {collection: 'safe', key: 'key', value: {v: 1}, vector: [1, 0]});
  h.context.__tideResolve(h.requests[0].id, null, null);
  assert.equal(await result, null);
});
test('AI generation and cancellation keep explicit request identity', async () => {
  const h = host();
  h.run(`tide.registerTool('generate', args => tide.ai.generate(args)); tide.registerTool('cancel', args => tide.ai.cancel(args.id));`);
  const result = h.call('tool', 'generate', {requestId: 'ai-1', providerId: 'p', messages: [{role:'user',content:'hello'}]});
  await h.tick();
  assert.equal(h.requests[0].method, 'ai.generate');
  const rejected = assert.rejects(result, /cancelled/);
  const cancel = h.call('tool', 'cancel', {id: 'ai-1'});
  await h.tick();
  assert.equal(h.requests[1].method, 'ai.cancel');
  assert.equal(h.requests[1].args.requestId, 'ai-1');
  h.context.__tideResolve(h.requests[1].id, true, null);
  h.context.__tideResolve(h.requests[0].id, null, 'cancelled');
  assert.equal(await cancel, true);
  await rejected;
});

test('general file API preserves names and scoped context through both SDK entry points', async () => {
  for (const expression of ['context.chat.sendFile(args)', 'tide.chat.sendFile(context, args)']) {
    const h = host();
    h.run(`tide.registerTool('file', async (args, context) => ${expression})`);
    const options = {resourceId: 'audio-1', fileName: '音乐.mp3', requestId: 'file-1'};
    const result = h.call('tool', 'file', {__tideInvocation: true, args: options, contextToken: 'file-token'});
    await h.tick();
    assert.equal(h.requests[0].method, 'chat.sendFile');
    assert.deepEqual(h.requests[0].args, {...options, contextToken: 'file-token'});
    h.context.__tideResolve(h.requests[0].id, {messageId: 'f', type: 'file', status: 'sent'}, null);
    assert.equal((await result).type, 'file');
    assert.ok(h.context.tide.capabilities.includes('chat.files'));
  }
});
