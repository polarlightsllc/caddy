FROM caddy:2-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/googleclouddns \
    --with github.com/caddyserver/cache-handler

FROM caddy:2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
