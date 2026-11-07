// Freeroam update server — no dependencies, Node 18+
//   GET /ui/...               in-game CEF UI (loaded by the gamemode)
//   GET /client/manifest.json list of client files + sha256 (used by launcher)
//   GET /client/files/<path>  client file download
//   GET /api/status           live server info (queried from open.mp over UDP)
//   GET /api/news             launcher news feed (news.json)
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const dgram = require("dgram");

const ROOT = path.resolve(__dirname, "..");
const CONFIG = {
  port: Number(process.env.PORT || 8080),
  gameHost: process.env.GAME_HOST || "127.0.0.1",
  gamePort: Number(process.env.GAME_PORT || 7777),
  // Address shown to players. Default: the host name the launcher used to reach us.
  publicHost: process.env.PUBLIC_HOST || "",
  uiDir: path.join(ROOT, "ui"),
  clientDir: path.join(ROOT, "client-files"),
  launcherDir: path.join(ROOT, "launcher-releases"),
  newsFile: path.join(__dirname, "news.json"),
};

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml",
  ".webm": "video/webm", ".ogg": "audio/ogg", ".woff2": "font/woff2",
  ".yml": "text/yaml; charset=utf-8", ".exe": "application/octet-stream",
};

// ---------- client manifest (cached, rebuilt when files change) ----------
let manifest = null;
function walk(dir, base = dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, base, out);
    else out.push(p);
  }
  return out;
}
function buildManifest() {
  const files = walk(CONFIG.clientDir).map(p => {
    const buf = fs.readFileSync(p);
    return {
      path: path.relative(CONFIG.clientDir, p).split(path.sep).join("/"),
      size: buf.length,
      sha256: crypto.createHash("sha256").update(buf).digest("hex"),
    };
  });
  const version = crypto.createHash("sha256").update(JSON.stringify(files)).digest("hex").slice(0, 12);
  manifest = { version, generated: new Date().toISOString(), files };
  console.log(`[manifest] ${files.length} files, version ${version}`);
}
let rebuildTimer;
function watchClientDir() {
  fs.mkdirSync(CONFIG.clientDir, { recursive: true });
  fs.watch(CONFIG.clientDir, { recursive: true }, () => {
    clearTimeout(rebuildTimer);
    rebuildTimer = setTimeout(buildManifest, 1000);
  });
}

// ---------- SA-MP / open.mp UDP query ----------
function queryServer(publicHost) {
  return new Promise(resolve => {
    const sock = dgram.createSocket("udp4");
    const ip = CONFIG.gameHost === "127.0.0.1" ? [127, 0, 0, 1] : CONFIG.gameHost.split(".").map(Number);
    const pkt = Buffer.alloc(11);
    pkt.write("SAMP", 0, "ascii");
    ip.forEach((b, i) => pkt.writeUInt8(b, 4 + i));
    pkt.writeUInt16LE(CONFIG.gamePort, 8);
    pkt.write("i", 10, "ascii");

    const done = data => { clearTimeout(t); sock.close(); resolve(data); };
    const t = setTimeout(() => done({ online: false }), 1500);
    sock.on("error", () => done({ online: false }));
    sock.on("message", msg => {
      try {
        let o = 11;
        const password = msg.readUInt8(o); o += 1;
        const players = msg.readUInt16LE(o); o += 2;
        const maxPlayers = msg.readUInt16LE(o); o += 2;
        const readStr = () => { const len = msg.readUInt32LE(o); o += 4; const s = msg.toString("latin1", o, o + len); o += len; return s; };
        const hostname = readStr(), gamemode = readStr(), language = readStr();
        done({ online: true, hostname, gamemode, language, players, maxPlayers, password: !!password,
               address: `${publicHost}:${CONFIG.gamePort}` });
      } catch { done({ online: false }); }
    });
    sock.send(pkt, CONFIG.gamePort, CONFIG.gameHost);
  });
}

// ---------- HTTP ----------
function sendJson(res, code, obj) {
  res.writeHead(code, { "Content-Type": MIME[".json"], "Cache-Control": "no-cache" });
  res.end(JSON.stringify(obj));
}
function sendFile(res, baseDir, rel) {
  const full = path.resolve(baseDir, "." + path.posix.normalize("/" + rel));
  if (!full.startsWith(baseDir + path.sep)) return sendJson(res, 403, { error: "forbidden" });
  fs.stat(full, (err, st) => {
    if (err || !st.isFile()) return sendJson(res, 404, { error: "not found" });
    res.writeHead(200, {
      "Content-Type": MIME[path.extname(full).toLowerCase()] || "application/octet-stream",
      "Content-Length": st.size,
      "Cache-Control": "no-cache",
    });
    fs.createReadStream(full).pipe(res);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  const p = decodeURIComponent(url.pathname);
  if (req.method !== "GET" && req.method !== "HEAD") return sendJson(res, 405, { error: "method not allowed" });

  if (p === "/" ) return sendJson(res, 200, { name: "freeroam-update-server", ok: true });
  if (p === "/api/status") {
    const host = CONFIG.publicHost || String(req.headers.host || "").replace(/:\d+$/, "") || "localhost";
    return sendJson(res, 200, await queryServer(host));
  }
  if (p === "/api/news") {
    try { return sendJson(res, 200, JSON.parse(fs.readFileSync(CONFIG.newsFile, "utf8"))); }
    catch { return sendJson(res, 200, []); }
  }
  if (p === "/client/manifest.json") return sendJson(res, 200, manifest);
  if (p.startsWith("/client/files/")) return sendFile(res, CONFIG.clientDir, p.slice("/client/files/".length));
  // Launcher releases (uploaded by build.bat): latest.yml + FreeroamLauncher-Setup-x.y.z.exe
  if (p === "/launcher/download") {
    try {
      const yml = fs.readFileSync(path.join(CONFIG.launcherDir, "latest.yml"), "utf8");
      const file = (yml.match(/^path:\s*(.+)$/m) || [])[1];
      if (file) { res.writeHead(302, { Location: "/launcher/" + encodeURIComponent(file.trim()) }); return res.end(); }
    } catch {}
    return sendJson(res, 404, { error: "no launcher release yet" });
  }
  if (p.startsWith("/launcher/")) return sendFile(res, CONFIG.launcherDir, p.slice("/launcher/".length));
  if (p === "/ui" || p === "/ui/") return sendFile(res, CONFIG.uiDir, "index.html");
  if (p.startsWith("/ui/")) return sendFile(res, CONFIG.uiDir, p.slice(4));
  sendJson(res, 404, { error: "not found" });
});

buildManifest();
watchClientDir();
server.listen(CONFIG.port, () => console.log(`[update-server] listening on :${CONFIG.port}`));
