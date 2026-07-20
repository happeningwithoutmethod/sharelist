FROM nginx:1.27-alpine

RUN apk add --no-cache gettext \
  && rm -f /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/nginx.conf
COPY templates /etc/nginx/templates
COPY docker-entrypoint.sh /docker-entrypoint-custom.sh
# Normalize CRLF if the script was edited on Windows.
RUN sed -i 's/\r$//' /docker-entrypoint-custom.sh \
  && chmod +x /docker-entrypoint-custom.sh

ENTRYPOINT ["/bin/sh", "/docker-entrypoint-custom.sh"]
