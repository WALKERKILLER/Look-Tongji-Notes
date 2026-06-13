"""Local HTTP server for the built llmwiki site.

Uses only Python stdlib. Binds to 127.0.0.1 by default so nothing is exposed
to the network unless the user explicitly passes --host 0.0.0.0.
"""

from __future__ import annotations

import http.server
import ssl
import socketserver
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

_VIDEO_PROXY_PATH = "/__llmwiki_video_proxy__"
_PROXY_HEADER_ALLOWLIST = {
    "Content-Type",
    "Content-Length",
    "Content-Range",
    "Accept-Ranges",
    "ETag",
    "Last-Modified",
    "Cache-Control",
}


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Like SimpleHTTPRequestHandler but with prettier logs and a branded
    404 response that pulls ``site/404.html`` (closes #387 U8) instead of
    falling back to the stdlib's plain-text error page."""

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        # Suppress per-request logs for a cleaner terminal.
        return

    def do_HEAD(self) -> None:  # noqa: N802
        if self.path.startswith(_VIDEO_PROXY_PATH):
            self._handle_video_proxy(send_body=False)
            return
        super().do_HEAD()

    def do_GET(self) -> None:  # noqa: N802
        if self.path.startswith(_VIDEO_PROXY_PATH):
            self._handle_video_proxy(send_body=True)
            return
        super().do_GET()

    def send_error(self, code: int, message: str | None = None,
                   explain: str | None = None) -> None:
        """Override the default error page so 404s pick up the branded
        ``404.html`` shipped by ``llmwiki build``. We deliberately keep the
        404 status code intact — the page is the *body* of the 404 response,
        not a redirect — so crawlers still see the right HTTP code.

        Falls back to the stdlib default for anything other than 404, or
        when ``404.html`` is missing (e.g. a partially-built site)."""
        if code == 404:
            try:
                # #py-m2 (#588): no longer relies on os.chdir(). The
                # SimpleHTTPRequestHandler's `directory` arg holds the
                # site root; we read 404.html from there explicitly.
                site_root = getattr(self, "directory", None)
                err_page = (Path(site_root) / "404.html") if site_root else Path("404.html")
                with open(err_page, "rb") as f:
                    body = f.read()
                self.send_response(404, message)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            except (FileNotFoundError, OSError):
                # 404.html doesn't exist — fall through to default behavior.
                pass
        super().send_error(code, message, explain)

    def _handle_video_proxy(self, *, send_body: bool) -> None:
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        raw_url = (params.get("url") or [""])[0].strip()
        if not raw_url:
            self.send_error(400, "missing url")
            return
        upstream = urllib.parse.urlparse(raw_url)
        if upstream.scheme not in {"http", "https"}:
            self.send_error(400, "unsupported scheme")
            return
        headers = {"User-Agent": "llmwiki-video-proxy/1.0"}
        range_header = self.headers.get("Range")
        if range_header:
            headers["Range"] = range_header
        request = urllib.request.Request(raw_url, headers=headers, method=self.command)
        try:
            with urllib.request.urlopen(request, timeout=60, context=ssl.create_default_context()) as resp:
                status = getattr(resp, "status", 200)
                reason = getattr(resp, "reason", "OK")
                self.send_response(status, reason)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
                for key, value in resp.headers.items():
                    if key.title() in _PROXY_HEADER_ALLOWLIST:
                        self.send_header(key, value)
                self.end_headers()
                if send_body:
                    while True:
                        chunk = resp.read(1024 * 256)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
        except urllib.error.HTTPError as exc:
            self.send_response(exc.code, exc.reason)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            if send_body:
                body = exc.read()
                if body:
                    self.wfile.write(body)
        except Exception as exc:  # pragma: no cover - network/runtime edge
            self.send_error(502, f"video proxy failed: {exc}")


class _ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


def serve_site(
    directory: Path,
    port: int = 8765,
    host: str = "127.0.0.1",
    open_browser: bool = False,
) -> int:
    directory = directory.expanduser().resolve()
    if not directory.exists():
        print(f"error: {directory} does not exist. Run `llmwiki build` first.")
        return 2
    # #py-m2 (#588): use SimpleHTTPRequestHandler's `directory=` kwarg
    # (Python 3.7+) instead of mutating global cwd. The previous
    # `os.chdir(directory)` call leaked process state — every test
    # using this function had to remember to chdir back, and
    # concurrent serve_site calls in tests would race.
    handler_factory = lambda *a, **kw: _QuietHandler(*a, directory=str(directory), **kw)
    url = f"http://{host}:{port}/"
    print(f"==> Serving {directory} at {url}")
    print("    Press Ctrl+C to stop.")
    try:
        with _ReusableTCPServer((host, port), handler_factory) as httpd:
            if open_browser:
                try:
                    webbrowser.open(url)
                except Exception:
                    pass
            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                print("\n  stopped.")
    except OSError as e:
        print(f"error: could not bind {host}:{port}: {e}")
        return 1
    return 0
