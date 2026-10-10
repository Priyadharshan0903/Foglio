import http from 'node:http';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const project = path.resolve(fileURLToPath(new URL('../', import.meta.url)));
const mime = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json', '.webp': 'image/webp', '.png': 'image/png', '.ttf': 'font/ttf', '.txt': 'text/plain; charset=utf-8', '.dmg': 'application/x-apple-diskimage' };
export function createServer({ built = false } = {}) {
const root = built ? path.join(project, 'dist') : project;
return http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://localhost');
    const pathname = decodeURIComponent(url.pathname);
    // Only the page and its published assets are served; never project files,
    // development dependencies, tests, or original high-resolution artwork.
    const allowed = ['/index.html', '/styles.css', '/app.js', '/release.json'];
    const relative = pathname === '/' ? 'index.html' : pathname.slice(1);
    if (!(pathname === '/' || allowed.includes(pathname) || /^\/(assets\/(images|fonts)|downloads)\/[\w.-]+$/.test(pathname))) {
      response.writeHead(404); response.end('Not found'); return;
    }
    const location = path.resolve(root, relative);
    if (!location.startsWith(root + path.sep)) { response.writeHead(404); response.end('Not found'); return; }
    const data = await fs.readFile(location);
    const headers = { 'Content-Type': mime[path.extname(location)] || 'application/octet-stream', 'Content-Length': data.length, 'X-Content-Type-Options': 'nosniff', 'Cache-Control': 'no-cache' };
    if (location.endsWith('.dmg')) headers['Content-Disposition'] = `attachment; filename="${path.basename(location)}"`;
    response.writeHead(200, headers);
    response.end(request.method === 'HEAD' ? undefined : data);
  } catch (error) {
    response.writeHead(error.code === 'ENOENT' ? 404 : 400); response.end('Not found');
  }
});
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
const built = process.argv.includes('--dist');
const argument = process.argv.indexOf('--port');
const port = argument >= 0 ? Number(process.argv[argument + 1]) : 4173;
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Choose a valid --port.');
const server = createServer({ built });
server.on('error', error => {
  console.error(error.code === 'EADDRINUSE'
    ? `Port ${port} is already in use. Open http://127.0.0.1:${port} or choose another --port.`
    : `Could not start the preview: ${error.message}`);
  process.exitCode = 1;
});
server.listen(port, '127.0.0.1', () => console.log(`Foglio landing page: http://127.0.0.1:${port}${built ? ' (production build)' : ''}`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
}
