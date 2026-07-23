# Share List React client — static build served under /web/
# Runtime config comes from a host-mounted .env (see docker-entrypoint.sh).
FROM node:22-alpine AS build
WORKDIR /app

COPY package.json yarn.lock* package-lock.json* ./
RUN if [ -f yarn.lock ]; then yarn install --frozen-lockfile; else npm install; fi

COPY . .

# Build-time defaults only; production values are injected from the mounted
# .env at container start via /env.js (see docker-entrypoint.sh).
ARG VITE_WS_URL=wss://sharelist.servehttp.com
ARG VITE_API_ORIGIN=https://sharelist.servehttp.com
ARG VITE_GOOGLE_CLIENT_ID=

ENV VITE_WS_URL=$VITE_WS_URL \
    VITE_API_ORIGIN=$VITE_API_ORIGIN \
    VITE_GOOGLE_CLIENT_ID=$VITE_GOOGLE_CLIENT_ID

RUN if [ -f yarn.lock ]; then yarn build; else npm run build; fi

FROM nginx:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
COPY --from=build /app/dist /usr/share/nginx/html

ENV ENV_FILE=/config/.env \
    ENV_JS_OUT=/usr/share/nginx/html/env.js

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
