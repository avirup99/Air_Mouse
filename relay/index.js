const WebSocket = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;
const ROOM_TTL_MS = 5 * 60 * 1000; // keep empty rooms for 5 min

const rooms = new Map();
// { code -> { host: WebSocket|null, deviceType, phones: Set<WebSocket>, deleteTimer } }

function makeCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let c = '';
  for (let i = 0; i < 6; i++) c += chars[Math.floor(Math.random() * chars.length)];
  return c;
}
function uniqueCode() {
  let c; do { c = makeCode(); } while (rooms.has(c)); return c;
}

function getRoom(code) { return rooms.get(code); }

function ensureRoom(code, deviceType) {
  if (!rooms.has(code))
    rooms.set(code, { host: null, deviceType, phones: new Set(), deleteTimer: null });
  return rooms.get(code);
}

function keepAlive(code) {
  const r = rooms.get(code);
  if (!r) return;
  clearTimeout(r.deleteTimer);
  r.deleteTimer = null;
}

function scheduleDrop(code) {
  const r = rooms.get(code);
  if (!r) return;
  clearTimeout(r.deleteTimer);
  r.deleteTimer = setTimeout(() => {
    const r2 = rooms.get(code);
    if (r2 && !r2.host && r2.phones.size === 0) {
      rooms.delete(code);
      console.log(`[room ${code}] expired`);
    }
  }, ROOM_TTL_MS);
}

function attachHost(ws, code, deviceType) {
  const room = ensureRoom(code, deviceType);
  room.host = ws;
  room.deviceType = deviceType;
  ws._code = code;
  ws._role = 'host';
  keepAlive(code);

  ws.send(JSON.stringify({ type: 'registered', code, deviceType }));

  // Tell any waiting phones the host is back
  room.phones.forEach(p => {
    if (p.readyState === WebSocket.OPEN)
      p.send(`status:connected:${deviceType}`);
  });

  ws.on('message', () => {});
  ws.on('close', () => {
    const r = rooms.get(code);
    if (r) {
      r.host = null;
      r.phones.forEach(p => {
        if (p.readyState === WebSocket.OPEN) p.send('status:host_disconnected');
      });
      scheduleDrop(code);
    }
    console.log(`[room ${code}] host left — room held for ${ROOM_TTL_MS/1000}s`);
  });
}

// ── HTTP ──────────────────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', rooms: rooms.size }));
    return;
  }
  res.writeHead(200); res.end('Air Mouse Relay');
});

// ── WebSocket ─────────────────────────────────────────────────────────────────
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
  const url = req.url || '/';
  console.log(`[ws] ${url}`);

  // ── /register?type=pc|tv  → fresh registration, always new code ───────────
  if (url.startsWith('/register')) {
    const params = new URLSearchParams(url.split('?')[1] || '');
    const deviceType = params.get('type') === 'tv' ? 'tv' : 'pc';
    const code = uniqueCode();
    console.log(`[room ${code}] registered (${deviceType})`);
    attachHost(ws, code, deviceType);
    return;
  }

  // ── /rejoin/:CODE?type=pc|tv  → PC agent slots back into existing room ─────
  // Used by agent.py after a reconnect so the same room code stays valid.
  const rejoinMatch = url.match(/^\/rejoin\/([A-Z0-9]{6})(\?.*)?$/);
  if (rejoinMatch) {
    const code = rejoinMatch[1];
    const params = new URLSearchParams((rejoinMatch[2] || '').slice(1));
    const deviceType = params.get('type') === 'tv' ? 'tv' : 'pc';
    // Room may or may not exist (phones could be waiting in it already).
    console.log(`[room ${code}] host rejoining`);
    attachHost(ws, code, deviceType);
    return;
  }

  // ── /phone/:CODE  → phone connects or reconnects ──────────────────────────
  const phoneMatch = url.match(/^\/phone\/([A-Z0-9]{6})$/);
  if (phoneMatch) {
    const code = phoneMatch[1].toUpperCase();
    const room = getRoom(code);

    if (!room) {
      ws.send('error:room_not_found');
      ws.close();
      return;
    }

    keepAlive(code);
    room.phones.add(ws);
    ws._code = code;
    ws._role = 'phone';

    const ready = room.host && room.host.readyState === WebSocket.OPEN;
    ws.send(ready
      ? `status:connected:${room.deviceType}`
      : `status:waiting_for_host:${room.deviceType}`);

    console.log(`[room ${code}] phone joined`);

    ws.on('message', (data) => {
      const r = rooms.get(code);
      if (r && r.host && r.host.readyState === WebSocket.OPEN)
        r.host.send(data.toString());
    });

    ws.on('close', () => {
      const r = rooms.get(code);
      if (r) { r.phones.delete(ws); scheduleDrop(code); }
      console.log(`[room ${code}] phone left — room held for ${ROOM_TTL_MS/1000}s`);
    });
    return;
  }

  ws.send('error:invalid_path');
  ws.close();
});

server.listen(PORT, () => console.log(`Relay on :${PORT}`));