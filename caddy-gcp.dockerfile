FROM caddy:2-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/googleclouddns \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/darkweak/storages/badger/caddy \
    --with github.com/techknowlogick/certmagic-s3=github.com/polarlightsllc/certmagic-s3@cdc749729efe345d70a85ce3d4654f2454bda73f \
    --with github.com/caddyserver/cache-handler \
    --with github.com/polarlightsllc/caddy-lb-spread@15df4f28e33a16d526175bd61c80bebdc7c90958

RUN /usr/bin/caddy list-modules | grep -x 'http.reverse_proxy.selection_policies.spread'

FROM caddy:2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
