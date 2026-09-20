"""Serve release bundles on loopback using their production subdirectory paths."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        for prefix, directory in self.server.mounts.items():
            if path.split('?')[0].startswith(prefix):
                original = self.directory
                self.directory = str(directory)
                try:
                    return super().translate_path('/' + path[len(prefix):])
                finally:
                    self.directory = original
        # Unmounted paths serve an empty directory, not repository source.
        return super().translate_path(path)

    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8866)
    parser.add_argument('--bundle', type=Path, default=Path('gallery/build/web'))
    parser.add_argument('--api-bundle', type=Path, default=Path('gallery/build/web-api'))
    args = parser.parse_args()
    empty = Path('build/codex-tmp/web-server-empty')
    empty.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, directory=str(empty.resolve())))
    server.mounts = {'/mediapipe_flutter/': args.bundle.resolve(), '/api-probe/': args.api_bundle.resolve()}
    server.serve_forever()


if __name__ == '__main__':
    main()
