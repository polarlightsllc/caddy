FROM caddy:2-builder@sha256:d842facfd63b960922e57444ff76fd8f0793a66dfdcf481af8026e1f4e6a39b4 AS builder

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

FROM caddy:2-alpine@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
