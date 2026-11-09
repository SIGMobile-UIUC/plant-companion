// Node 22+; build browser_persistence_smoke.dart first. Chrome uses a temporary
// profile under build/, never the user's existing browser data. No npm packages.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const root = path.resolve(process.argv[2] ?? 'build/browser-persistence-smoke');
const chrome = process.env.CHROME_EXECUTABLE ??
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profile = await fs.mkdtemp(path.join(root, '.smoke-profile-'));
const mime = { '.html': 'text/html', '.js': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json' };
const server = http.createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!file.startsWith(root + path.sep)) throw Error('Invalid path');
    res.setHeader('Content-Type', mime[path.extname(file)] ?? 'application/octet-stream');
    res.setHeader('Cache-Control', 'no-store');
    // Normal localhost deployment: deliberately no COOP/COEP isolation headers.
    res.end(await fs.readFile(file));
  } catch {
    res.writeHead(404).end();
  }
});
server.listen(0, '127.0.0.1');
await once(server, 'listening');
const origin = `http://127.0.0.1:${server.address().port}`;

async function until(action, description, timeout = 60000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const result = await action();
    if (result) return result;
    await delay(100);
  }
  throw Error(`Timed out: ${description}`);
}

class Cdp {
  constructor(socket) {
    this.socket = socket;
    this.sequence = 0;
    this.pending = new Map();
    socket.addEventListener('message', ({ data }) => {
      const message = JSON.parse(data);
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      clearTimeout(pending.timer);
      if (message.error) pending.reject(Error(JSON.stringify(message.error)));
      else pending.resolve(message.result);
    });
  }
  static async open(url) {
    const socket = new WebSocket(url);
    await once(socket, 'open');
    return new Cdp(socket);
  }
  call(method, params = {}) {
    const id = ++this.sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(Error(`CDP timed out: ${method}`));
      }, 15000);
      this.pending.set(id, { resolve, reject, timer });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }
  async evaluate(expression) {
    const response = await this.call('Runtime.evaluate', { expression, returnByValue: true });
    if (response.exceptionDetails) throw Error(JSON.stringify(response.exceptionDetails));
    return response.result.value;
  }
  close() { this.socket.close(); }
}

let running;
async function launch() {
  await fs.rm(path.join(profile, 'DevToolsActivePort'), { force: true });
  const process = spawn(chrome, [
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--disable-background-networking', '--remote-debugging-port=0',
    `--user-data-dir=${profile}`, 'about:blank',
  ], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
  const launched = { process, exited: once(process, 'exit'), stderr: '' };
  running = launched;
  process.stderr.on('data', data => { launched.stderr = (launched.stderr + data).slice(-6000); });
  const port = await until(async () => {
    try { return (await fs.readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]; }
    catch { return null; }
  }, 'Chrome debugging port');
  const endpoint = `http://127.0.0.1:${port}`;
  const version = await (await fetch(endpoint + '/json/version')).json();
  running.browser = await Cdp.open(version.webSocketDebuggerUrl);
  const tab = await (await fetch(endpoint + '/json/new?about:blank', { method: 'PUT' })).json();
  running.tab = await Cdp.open(tab.webSocketDebuggerUrl);
  await running.tab.call('Page.enable');
  console.log(`Chrome: ${version.Browser}`);
}

async function stage(name, reload = false) {
  await running.tab.evaluate('globalThis.plantCompanionSmokeResult = null');
  if (reload) await running.tab.call('Page.reload', { ignoreCache: true });
  else await running.tab.call('Page.navigate', { url: `${origin}/?stage=${name}` });
  const value = await until(async () => {
    const result = await running.tab.evaluate('globalThis.plantCompanionSmokeResult || null');
    return result ? JSON.parse(result) : null;
  }, `SQLite ${name}${reload ? ' after reload' : ''}`);
  assert.equal(value.ok, true, JSON.stringify(value));
  assert.equal(value.stage, name);
  console.log(JSON.stringify({ ...value, reload }));
  return value;
}

async function shutdown() {
  if (!running) return;
  const current = running;
  if (current.browser) {
    try { await current.browser.call('Browser.close'); } catch { /* Browser may close first. */ }
  } else current.process.kill();
  try {
    await Promise.race([current.exited, delay(15000, undefined, { ref: false }).then(() => { throw Error('Chrome did not exit'); })]);
  } catch (error) {
    current.process.kill();
    throw error;
  } finally {
    current.tab?.close();
    current.browser?.close();
    running = null;
  }
}

try {
  await launch();
  const created = await stage('create');
  await stage('edit');
  const before = await stage('verify');
  assert.equal(before.packetId, created.packetId);
  assert.equal(before.recordedAt, created.recordedAt);
  assert.deepEqual(await stage('verify', true), before);
  await shutdown();
  await launch(); // Completely new Chrome process, same origin and disk profile.
  assert.deepEqual(await stage('verify'), before);
  console.log(`PASS: create, edit, reload, full Chrome restart; profile=${profile}`);
} catch (error) {
  console.error(running?.stderr ?? '');
  throw error;
} finally {
  await shutdown();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
