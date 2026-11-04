FROM caddy:2.11.7-builder-alpine@sha256:95a5e7e2692b5eb9545aadc5b90a39f6f509bee59c9508a493f83ee902eaef63 AS builder

# Keep the deployed module versions; patch only Souin's abort propagation.
RUN go mod download github.com/darkweak/souin@v1.7.9 \
    && mkdir -p /src \
    && cp -a /go/pkg/mod/github.com/darkweak/souin@v1.7.9 /src/souin \
    && chmod -R u+w /src/souin
COPY patches/souin-v1.7.9-abort.patch /tmp/souin-abort.patch
COPY tests/abort_response_test.go /src/souin/pkg/middleware/abort_response_test.go
RUN cd /src/souin \
    && git apply /tmp/souin-abort.patch \
    && go test -tags nobadger,nomysql,nopgx ./pkg/middleware -skip '^TestSend_MultipartRange$'

RUN xcaddy build v2.11.7 \
    --with github.com/caddy-dns/googleclouddns@v1.1.0 \
    --with github.com/mholt/caddy-ratelimit@v0.1.0 \
    --with github.com/darkweak/storages/badger/caddy@v0.0.20 \
    --with github.com/techknowlogick/certmagic-s3=github.com/polarlightsllc/certmagic-s3@cdc749729efe345d70a85ce3d4654f2454bda73f \
    --with github.com/caddyserver/cache-handler@v0.17.0 \
    --with github.com/polarlightsllc/caddy-lb-spread@v0.1.0 \
    --replace github.com/darkweak/souin=/src/souin

RUN /usr/bin/caddy list-modules | grep -x 'http.reverse_proxy.selection_policies.spread'

FROM caddy:2.11.7-alpine@sha256:e70b164da81ef698b3ad19af799ea6086ce6d9e48ed4079eb9fe26f6fbf14ee5

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
