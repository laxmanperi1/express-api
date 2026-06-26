const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { app, markReady, markNotReady } = require('./app');

function request(path) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, () => {
      const { port } = server.address();
      http.get(`http://127.0.0.1:${port}${path}`, (res) => {
        let body = '';
        res.on('data', (chunk) => { body += chunk; });
        res.on('end', () => {
          server.close();
          resolve({ status: res.statusCode, body });
        });
      }).on('error', (err) => {
        server.close();
        reject(err);
      });
    });
  });
}

describe('express-api', () => {
  beforeEach(() => {
    markReady();
  });

  test('GET /health returns ok when ready', async () => {
    const { status, body } = await request('/health');
    assert.equal(status, 200);
    assert.match(body, /"status":"ok"/);
  });

  test('GET /health/live returns alive', async () => {
    const { status, body } = await request('/health/live');
    assert.equal(status, 200);
    assert.match(body, /"status":"alive"/);
  });

  test('GET /health/ready returns 503 when not ready', async () => {
    markNotReady();
    const { status, body } = await request('/health/ready');
    assert.equal(status, 503);
    assert.match(body, /"status":"not_ready"/);
  });

  test('GET /health/ready returns ready when marked ready', async () => {
    const { status, body } = await request('/health/ready');
    assert.equal(status, 200);
    assert.match(body, /"status":"ready"/);
  });

  test('GET /api returns welcome message', async () => {
    const { status, body } = await request('/api');
    assert.equal(status, 200);
    assert.match(body, /Welcome to the API/);
  });

  test('GET /metrics returns prometheus format', async () => {
    const { status, body } = await request('/metrics');
    assert.equal(status, 200);
    assert.match(body, /process_cpu/);
  });
});
