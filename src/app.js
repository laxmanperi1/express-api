const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const promClient = require('prom-client');

const app = express();
const startTime = Date.now();
const register = promClient.register;

promClient.collectDefaultMetrics({ register });

app.use(helmet({
  contentSecurityPolicy: false,
}));

app.use(express.json({ limit: '10kb' }));

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});

app.get('/health', (_req, res) => {
  res.status(200).json({
    status: 'ok',
    uptime: Math.floor((Date.now() - startTime) / 1000),
    timestamp: new Date().toISOString(),
  });
});

app.get('/api', apiLimiter, (_req, res) => {
  res.json({
    message: 'Welcome to the API',
    version: '1.0.0',
  });
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

module.exports = { app, register };
