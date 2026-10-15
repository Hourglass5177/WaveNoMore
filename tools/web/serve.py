"""本地 Web 试玩服务器：为 Godot 多线程和 Spine 扩展提供隔离响应头。"""
import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm', '.pck': 'application/octet-stream'}
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
        super().end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', default=str(Path(__file__).resolve().parent))
    parser.add_argument('--port', type=int, default=8067)
    args = parser.parse_args()
    handler = functools.partial(Handler, directory=str(Path(args.directory).resolve()))
    print(f'本地试玩：http://localhost:{args.port}/', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), handler).serve_forever()
