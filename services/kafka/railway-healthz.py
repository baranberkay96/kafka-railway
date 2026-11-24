#!/usr/bin/env python3
"""Private /healthz on $PORT for Railway's healthcheck (STANDARD 8.34).

200 while the broker accepts TCP connections on its container-local
listener, 503 otherwise. The body carries the user-sync state written by
railway-kafka-users. Nothing secret is served.
"""
import http.server
import os
import socket

STATE_FILE = "/tmp/railway-kafka-state"
BROKER = ("127.0.0.1", 9095)


def port() -> int:
    value = os.environ.get("PORT", "")
    return int(value) if value.isdigit() and 1 <= int(value) <= 65535 else 8080


def broker_up() -> bool:
    try:
        with socket.create_connection(BROKER, timeout=2):
            return True
    except OSError:
        return False


def state() -> str:
    try:
        with open(STATE_FILE, encoding="utf-8") as handle:
            return handle.read(200).strip() or "starting"
    except OSError:
        return "starting"


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "railway-kafka-healthz"
    sys_version = ""

    def do_GET(self) -> None:  # noqa: N802
        if self.path.split("?", 1)[0] not in ("/healthz", "/"):
            self.send_error(404)
            return
        up = broker_up()
        body = f"{'ok' if up else 'broker not ready'} {state()}\n".encode()
        self.send_response(200 if up else 503)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_HEAD = do_GET

    def log_message(self, *args) -> None:
        return


class DualStackServer(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6
    daemon_threads = True

    def server_bind(self) -> None:
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


def main() -> None:
    try:
        server = DualStackServer(("::", port()), Handler)
    except OSError:
        server = http.server.ThreadingHTTPServer(("0.0.0.0", port()), Handler)
        server.daemon_threads = True
    server.serve_forever()


if __name__ == "__main__":
    main()
