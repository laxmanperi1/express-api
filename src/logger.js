const pino = require('pino');
const { randomUUID } = require('node:crypto');

const isProduction = process.env.NODE_ENV === 'production';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  ...(isProduction
    ? {}
    : {
        transport: {
          target: 'pino-pretty',
          options: { colorize: true, singleLine: true },
        },
      }),
  base: {
    service: 'express-api',
    version: process.env.APP_VERSION || '1.0.0',
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

function createRequestId() {
  return randomUUID();
}

module.exports = { logger, createRequestId };
