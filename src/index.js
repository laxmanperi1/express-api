const { app, markReady, markNotReady, logger } = require('./app');

const PORT = process.env.PORT || 3000;

const server = app.listen(PORT, () => {
  logger.info({ port: PORT }, 'Server started');
  markReady();
});

function shutdown(signal) {
  logger.info({ signal }, 'Shutdown signal received');
  markNotReady();

  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });

  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
