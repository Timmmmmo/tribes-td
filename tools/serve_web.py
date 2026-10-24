"""带正确 MIME 的静态服务器 —— 给 Godot Web 导出做本地验证。

python -m http.server 不知道 .wasm / .pck 的类型，Chrome 会拒绝
WebAssembly.instantiateStreaming，控制台一片红。这里补上。

用法：
    python tools/serve_web.py <目录> [端口]
"""

import functools
import http.server
import os
import socketserver
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
        ".json": "application/json",
    }

    def end_headers(self) -> None:
        # 单线程版 Godot 不需要 COOP/COEP，但加上不影响；留注释以免后人误删
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s\n" % (fmt % args))


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    directory = os.path.abspath(sys.argv[1])
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8124
    handler = functools.partial(Handler, directory=directory)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", port), handler) as httpd:
        print("serving %s at http://127.0.0.1:%d" % (directory, port), flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
