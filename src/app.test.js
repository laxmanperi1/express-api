const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { app } = require('./app');

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
  test('GET /health returns ok', async () => {
    const { status, body } = await request('/health');
    assert.equal(status, 200);
    assert.match(body, /"status":"ok"/);
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
