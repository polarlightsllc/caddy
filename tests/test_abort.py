#!/usr/bin/env python3
"""Exercise the built image against a synthetic origin that truncates a body."""
import collections
import concurrent.futures
import http.client
import http.server
import difflib
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid

IMAGE = sys.argv[1]
COUNTS = collections.Counter()
LOCK = threading.Lock()


class Origin(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        with LOCK:
            COUNTS[self.path] += 1
        self.send_response(200)
        self.send_header("Content-Type", "application/javascript")
        self.send_header("Cache-Control", "public, max-age=60")
        if self.path.startswith("/abort"):
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            self.wfile.write(b"6\r\nprefix\r\n")
            self.wfile.flush()
            time.sleep(0.15)
            self.close_connection = True
            self.connection.shutdown(socket.SHUT_RDWR)
        else:
            self.send_header("Content-Length", "7")
            self.end_headers()
            self.wfile.write(b"healthy")


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True).strip()


def fetch(base, path):
    with urllib.request.urlopen(base + path, timeout=10) as response:
        return response.read(), response.headers


def aborted(base, path):
    try:
        body, _ = fetch(base, path)
    except urllib.error.HTTPError as error:
        raise AssertionError(f"abort became a completed HTTP {error.code} response") from error
    except (http.client.HTTPException, urllib.error.URLError, ConnectionError):
        return
    raise AssertionError(f"aborted response completed successfully: {body!r}")


def module_graph(text):
    modules = {}
    current = None
    for line in text.splitlines():
        fields = line.split()
        if fields and fields[0] == "dep":
            current = fields[1]
            if current != "github.com/darkweak/souin":
                modules[current] = " ".join(fields[2:])
        elif fields and fields[0] == "=>" and current != "github.com/darkweak/souin":
            modules[current] += " => " + " ".join(fields[1:])
    return sorted(f"{name} {version}" for name, version in modules.items())


def main():
    expected = module_graph(pathlib.Path(__file__).with_name("modules-v1.6.0.txt").read_text())
    actual = module_graph(docker("run", "--rm", "--entrypoint", "caddy", IMAGE, "build-info"))
    assert actual == expected, "Dependency drift:\n" + "\n".join(difflib.unified_diff(expected, actual))
    origin = http.server.ThreadingHTTPServer(("0.0.0.0", 0), Origin)
    thread = threading.Thread(target=origin.serve_forever, daemon=True)
    thread.start()
    name = "caddy-abort-test-" + uuid.uuid4().hex[:12]
    try:
        with tempfile.TemporaryDirectory(prefix="caddy-abort-") as directory:
            config = pathlib.Path(directory, "Caddyfile")
            config.write_text("""{
    admin off
    auto_https off
    order cache before reverse_proxy
}
:8080 {
    cache {
        ttl 60s
        default_cache_control public, max-age=60
    }
    reverse_proxy host.docker.internal:%d
}
""" % origin.server_port)
            docker("run", "-d", "--name", name,
                   "--add-host=host.docker.internal:host-gateway",
                   "-p", "127.0.0.1::8080",
                   "-v", f"{config}:/etc/caddy/Caddyfile:ro", IMAGE)
            port = docker("port", name, "8080/tcp").rsplit(":", 1)[1]
            base = "http://127.0.0.1:" + port
            deadline = time.monotonic() + 30
            while True:
                try:
                    fetch(base, "/ready")
                    break
                except (OSError, http.client.HTTPException):
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.1)
            for _ in range(2):
                aborted(base, "/abort.js")
            assert COUNTS["/abort.js"] == 2, COUNTS
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(lambda _: aborted(base, "/abort-concurrent.js"), range(8)))
            previous = COUNTS["/abort-concurrent.js"]
            aborted(base, "/abort-concurrent.js")
            assert COUNTS["/abort-concurrent.js"] > previous, COUNTS
            body, _ = fetch(base, "/healthy.js")
            assert body == b"healthy", body
            body, headers = fetch(base, "/healthy.js")
            assert body == b"healthy", body
            assert "hit" in headers.get("Cache-Status", ""), dict(headers)
            assert COUNTS["/healthy.js"] == 1, COUNTS
            assert docker("inspect", "-f", "{{.State.Running}}", name) == "true"
            print("PASS: sequential and coalesced aborts fail, are not cached; healthy cache hits; Caddy survives")
    except BaseException:
        subprocess.run(["docker", "logs", "--tail", "30", name], check=False)
        raise
    finally:
        subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, check=False)
        origin.shutdown()
        origin.server_close()
        thread.join()


if __name__ == "__main__":
    main()
