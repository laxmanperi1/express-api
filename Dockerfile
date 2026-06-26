# syntax=docker/dockerfile:1

ARG NODE_VERSION=20.18.0

# --- Stage 1: install production dependencies ---
FROM node:${NODE_VERSION}-alpine AS deps

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci --omit=dev \
  && npm cache clean --force

# --- Stage 2: run tests ---
FROM deps AS test

COPY src ./src

RUN npm ci \
  && npm test \
  && npm cache clean --force

# --- Stage 3: minimal production runtime ---
FROM node:${NODE_VERSION}-alpine AS production

WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000

RUN apk add --no-cache dumb-init \
  && addgroup -g 1001 -S appgroup \
  && adduser -S appuser -u 1001 -G appgroup

COPY --from=deps --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --chown=appuser:appgroup package.json package-lock.json ./
COPY --chown=appuser:appgroup src ./src

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:' + (process.env.PORT || 3000) + '/health/live', (r) => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/index.js"]
