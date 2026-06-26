const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const promClient = require('prom-client');
const pinoHttp = require('pino-http');
const { logger, createRequestId } = require('./logger');

const app = express();
const startTime = Date.now();
const register = promClient.register;

let isReady = false;

promClient.collectDefaultMetrics({ register });

app.use(pinoHttp({
  logger,
  genReqId: (req) => req.headers['x-request-id'] || createRequestId(),
  customLogLevel: (_req, res, err) => {
    if (err || res.statusCode >= 500) return 'error';
    if (res.statusCode >= 400) return 'warn';
    return 'info';
  },
  customSuccessMessage: (req, res) => `${req.method} ${req.url} ${res.statusCode}`,
  customErrorMessage: (req, res) => `${req.method} ${req.url} ${res.statusCode}`,
  autoLogging: {
    ignore: (req) => req.url === '/metrics' || req.url.startsWith('/health'),
  },
}));

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

function getHealthPayload() {
  return {
    status: 'ok',
    uptime: Math.floor((Date.now() - startTime) / 1000),
    timestamp: new Date().toISOString(),
  };
}

// Liveness: process is alive and event loop is responsive
app.get('/health/live', (_req, res) => {
  res.status(200).json({ ...getHealthPayload(), status: 'alive' });
});

// Readiness: app is ready to accept traffic
app.get('/health/ready', (_req, res) => {
  if (!isReady) {
    return res.status(503).json({ status: 'not_ready', timestamp: new Date().toISOString() });
  }
  res.status(200).json({ ...getHealthPayload(), status: 'ready' });
});

// Combined health check (backward compatible)
app.get('/health', (_req, res) => {
  if (!isReady) {
    return res.status(503).json({ status: 'not_ready', timestamp: new Date().toISOString() });
  }
  res.status(200).json(getHealthPayload());
});

app.get('/api', apiLimiter, (req, res) => {
  req.log.info({ route: '/api' }, 'API request handled');
  res.json({
    message: 'Welcome to the API',
    version: '1.0.0',
  });
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

function markReady() {
  isReady = true;
  logger.info('Application marked ready');
}

function markNotReady() {
  isReady = false;
  logger.warn('Application marked not ready');
}

module.exports = { app, register, markReady, markNotReady, logger };
