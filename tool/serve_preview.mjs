import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../build/web');
const types = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.otf': 'font/otf', '.bin': 'application/octet-stream' };

http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://127.0.0.1');
    const requested = path.resolve(root, `.${decodeURIComponent(url.pathname)}`);
    const relative = path.relative(root, requested);
    if (relative.startsWith('..') || path.isAbsolute(relative)) {
      response.writeHead(403).end(); return;
    }
    let target = requested;
    const info = await stat(target).catch(() => null);
    if (info?.isDirectory()) target = path.join(target, 'index.html');
    if (!info && !path.extname(target)) target = path.join(root, 'index.html');
    const body = await readFile(target);
    response.writeHead(200, {
      'Content-Type': types[path.extname(target)] ?? 'application/octet-stream',
      'Cache-Control': 'no-store',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    });
    response.end(body);
  } catch {
    response.writeHead(404).end('Not found');
  }
}).listen(7357, '127.0.0.1', () => console.log('ISYARATIN preview: http://127.0.0.1:7357'));
