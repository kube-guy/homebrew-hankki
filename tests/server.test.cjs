const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawn, spawnSync } = require('node:child_process');
const http = require('node:http');
const net = require('node:net');
const path = require('node:path');
const { once } = require('node:events');

const cli = path.resolve(__dirname, '../bin/hankki.cjs');

function request(port, pathname, options = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port, path: pathname, ...options }, res => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
    });
    req.on('error', reject);
    req.end();
  });
}

test('CLI reports version and rejects invalid ports', () => {
  const version = spawnSync(process.execPath, [cli, '--version'], { encoding: 'utf8' });
  assert.equal(version.status, 0);
  assert.match(version.stdout, /hankki 0\.2\.0/);
  for (const port of ['1023', '65536', 'abc', '4173.5']) {
    const result = spawnSync(process.execPath, [cli, '--port', port, '--no-open'], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /1024–65535/);
  }
});

test('local server serves the app and rejects unsafe requests', { timeout: 10000 }, async t => {
  const probe = net.createServer();
  probe.listen(0, '127.0.0.1');
  await once(probe, 'listening');
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const child = spawn(process.execPath, [cli, '--port', String(port), '--no-open'], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const exited = once(child, 'exit');
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
    await exited;
  });
  await Promise.race([
    once(child.stdout, 'data'),
    exited.then(([code]) => { throw new Error(`Server exited before startup: ${code}`); }),
  ]);

  const health = await request(port, '/health');
  assert.equal(health.status, 200);
  assert.deepEqual(JSON.parse(health.body), { app: 'hankki', version: '0.2.0' });
  const page = await request(port, '/', { headers: { Host: `localhost:${port}` } });
  assert.equal(page.status, 200);
  assert.match(page.body, /한 끼/);
  assert.match(page.headers['content-type'], /text\/html/);
  assert.equal(page.headers['x-content-type-options'], 'nosniff');
  const head = await request(port, '/', { method: 'HEAD' });
  assert.equal(head.status, 200);
  assert.equal(head.body, '');
  assert.equal(head.headers['content-length'], page.headers['content-length']);
  assert.equal((await request(port, '/', { method: 'POST' })).status, 405);
  assert.equal((await request(port, '/', { headers: { Host: 'evil.example' } })).status, 403);
  assert.equal((await request(port, '/%2e%2e%2fpackage.json')).status, 403);
  assert.equal((await request(port, '/%ZZ')).status, 400);
  assert.equal((await request(port, '/missing.js')).status, 404);
});
