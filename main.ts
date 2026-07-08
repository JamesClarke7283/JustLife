// Just Life — server entry + desktop app entrypoint.
// Serves static files from public/ to the desktop window. The desktop
// backend wires the native window to this local Deno.serve() handler
// automatically — no manual port needed.
//
// Files are resolved relative to the project root (cwd). `deno desktop`
// compiles main.ts into a .so whose import.meta.url points at a cache
// directory, but the process cwd is still the project folder, so cwd is
// the reliable anchor. The desktop tasks in deno.json pass --allow-read.

const PUBLIC_DIR = `${Deno.cwd()}/public/`;

const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2",
  ".ico": "image/x-icon",
};

function resolvePath(url: string): string | null {
  let path = url.split("?")[0];
  if (path === "/" || path === "") path = "/index.html";
  const clean = path.replace(/^\/+/, "");
  const target = PUBLIC_DIR + clean;
  // Prevent path traversal: target must start with PUBLIC_DIR
  if (!target.startsWith(PUBLIC_DIR)) return null;
  return target;
}

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const filePath = resolvePath(url.pathname);
  if (!filePath) return new Response("Forbidden", { status: 403 });

  try {
    const file = await Deno.open(filePath, { read: true });
    const ext = filePath.slice(filePath.lastIndexOf("."));
    const contentType = MIME[ext] ?? "application/octet-stream";
    return new Response(file.readable, {
      headers: { "content-type": contentType },
    });
  } catch {
    return new Response("Not Found", {
      status: 404,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }
}

Deno.serve(handler);