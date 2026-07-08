// Just Life — server entry + desktop app entrypoint.
// Serves static files from public/ to the desktop window. The desktop
// backend wires the native window to this local Deno.serve() handler
// automatically — no manual port needed.
//
// When compiled with `deno desktop`, the `public/` directory is embedded
// via `--include public/`. We resolve it from several candidate locations
// to support both dev (cwd/public) and compiled (embedded temp dir) modes.

const CANDIDATES = [
  `${Deno.cwd()}/public/`,
  new URL('./public/', import.meta.url).pathname,
];

function findPublicDir(): string {
  for (const dir of CANDIDATES) {
    try {
      Deno.readDirSync(dir);
      return dir;
    } catch {
      // keep trying
    }
  }
  // last resort — return cwd-based path; the 404 handler will deal with it
  return CANDIDATES[0];
}

const PUBLIC_DIR = findPublicDir();

const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.ogg': 'audio/ogg',
  '.mp3': 'audio/mpeg',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
};

function resolvePath(url: string): string | null {
  let path = url.split('?')[0];
  if (path === '/' || path === '') path = '/index.html';
  const clean = path.replace(/^\/+/, '');
  const target = PUBLIC_DIR + clean;
  if (!target.startsWith(PUBLIC_DIR)) return null;
  return target;
}

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const filePath = resolvePath(url.pathname);
  if (!filePath) return new Response('Forbidden', { status: 403 });

  try {
    const file = await Deno.open(filePath, { read: true });
    const ext = filePath.slice(filePath.lastIndexOf('.'));
    const contentType = MIME[ext] ?? 'application/octet-stream';
    return new Response(file.readable, {
      headers: { 'content-type': contentType },
    });
  } catch {
    return new Response('Not Found', {
      status: 404,
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    });
  }
}

Deno.serve(handler);
