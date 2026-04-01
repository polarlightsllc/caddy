FROM caddy:2-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/googleclouddns \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/darkweak/storages/badger/caddy \
    --with github.com/techknowlogick/certmagic-s3=github.com/polarlightsllc/certmagic-s3@2e454d75743a058c7e6278180f55deb6c72c3e10 \
    --with github.com/caddyserver/cache-handler

FROM caddy:2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
