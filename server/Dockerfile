# Share List relay server
# Build:  docker compose build
# Run:    docker compose up -d

FROM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build \
  && npm prune --omit=dev

FROM node:22-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000 \
    HTTPS_PORT=3443 \
    ENABLE_HTTP=true \
    ENABLE_HTTPS=false \
    ENV_FILE=/app/.env

# No extra apk packages — BusyBox su is enough to drop privileges after reading .env.
RUN addgroup -S sharelist && adduser -S sharelist -G sharelist \
  && mkdir -p /app/data /app/certs \
  && chown -R sharelist:sharelist /app

COPY --from=build --chown=sharelist:sharelist /app/package.json /app/package-lock.json ./
COPY --from=build --chown=sharelist:sharelist /app/node_modules ./node_modules
COPY --from=build --chown=sharelist:sharelist /app/dist ./dist
COPY --chown=sharelist:sharelist public ./public
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN sed -i 's/\r$//' /docker-entrypoint.sh \
  && chmod +x /docker-entrypoint.sh

# Entrypoint runs as root briefly to read the mounted .env, then drops to sharelist.
USER root

EXPOSE 3000 3443

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/health').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/docker-entrypoint.sh"]
