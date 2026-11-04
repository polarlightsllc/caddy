# Caddy GCP image

The image retains the Caddy and plugin versions shipped in `v1.6.0`, with a
minimal patch to Souin `v1.7.9` to propagate `http.ErrAbortHandler` back to the
HTTP request goroutine. The upstream goroutine returns the sentinel through the
existing error channel; only the request goroutine re-panics. An incomplete
cacheable origin response must not become a successful partial response or a
cache entry.

Base images are pinned by multi-platform digest and plugins by version/commit.
`tests/modules-v1.6.0.txt` records the deployed binary's Go module versions and
checksums. The image regression rejects dependency drift other than the local
Souin replacement. No cache configuration changes are made.

## Reproduce

```sh
docker build -f caddy-gcp.dockerfile -t caddy-abort-test:local .
python3 tests/test_abort.py caddy-abort-test:local
```

The Python test uses only synthetic content. It checks sequential and coalesced
truncated JavaScript responses, retries reaching the origin, healthy cache hits,
and server survival. It cleans up its container and temporary configuration.
Against `ghcr.io/polarlightsllc/caddy-gcp:v1.6.0` it fails because the truncated
response completes successfully with `prefix`.

The builder runs the middleware tests, excluding `TestSend_MultipartRange`,
which also fails on pristine Souin `v1.7.9` under the pinned Go toolchain
(expected 206, got 200). That pre-existing range behavior is outside this patch.
The abort regression itself must pass and send no buffered partial content.

## Publishing

Open a ready-for-review PR. The existing workflow builds and tests native
`linux/amd64` and `linux/arm64` images before publishing. Merging a conventional
`fix:` commit runs semantic-release; its version tag triggers publication to
`ghcr.io/polarlightsllc/caddy-gcp`. Deploy the resulting manifest digest, not a
mutable major/minor or SHA alias. The same source tag and Dockerfile can rebuild
the image for validation fallbacks. Deployment configuration lives elsewhere.
