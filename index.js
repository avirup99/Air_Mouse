const WebSocket = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;

// rooms: { code -> { host: WebSocket|null, deviceType: 'pc'|'tv', phones: Set<WebSocket> } }
const rooms = new Map();

function getOrCreateRoom(code, deviceType = 'pc') {
  if (!rooms.has(code)) {
    rooms.set(code, { host: null, deviceType, phones: new Set() });
  }
  return rooms.get(code);
}

function cleanupRoom(code) {
  const room = rooms.get(code);
  if (room && !room.host && room.phones.size === 0) {
    rooms.delete(code);
    console.log(`[room ${code}] deleted`);
  }
}

function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return code;
}

function makeUniqueCode() {
  let code;
  do { code = generateCode(); } while (rooms.has(code));
  return code;
}

// ── HTTP ──────────────────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', rooms: rooms.size }));
    return;
  }
  res.writeHead(200);
  res.end('Air Mouse Relay');
});

// ── WebSocket ─────────────────────────────────────────────────────────────────
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
  const url = req.url || '/';
  console.log(`[ws] ${url}`);

  // ── Host registers (PC or TV) ─────────────────────────────────────────────
  // /register?type=pc  or  /register?type=tv
  if (url.startsWith('/register')) {
    const params = new URLSearchParams(url.split('?')[1] || '');
    const deviceType = params.get('type') === 'tv' ? 'tv' : 'pc';
    const code = makeUniqueCode();
    const room = getOrCreateRoom(code, deviceType);
    room.host = ws;
    room.deviceType = deviceType;
    ws._code = code;
    ws._role = 'host';

    ws.send(JSON.stringify({ type: 'registered', code, deviceType }));
    console.log(`[room ${code}] ${deviceType} registered`);

    ws.on('message', () => {});
    ws.on('close', () => {
      const r = rooms.get(code);
      if (r) {
        r.host = null;
        r.phones.forEach(p => {
          if (p.readyState === WebSocket.OPEN)
            p.send('status:host_disconnected');
        });
        cleanupRoom(code);
      }
      console.log(`[room ${code}] host disconnected`);
    });
    return;
  }

  // ── Host reconnects ───────────────────────────────────────────────────────
  const hostMatch = url.match(/^\/host\/([A-Z0-9]{6})\?type=(pc|tv)$/);
  if (hostMatch) {
    const code = hostMatch[1];
    const deviceType = hostMatch[2];
    const room = getOrCreateRoom(code, deviceType);
    room.host = ws;
    room.deviceType = deviceType;
    ws._code = code;
    ws._role = 'host';

    ws.send(JSON.stringify({ type: 'registered', code, deviceType }));
    room.phones.forEach(p => {
      if (p.readyState === WebSocket.OPEN) p.send('status:connected');
    });
    console.log(`[room ${code}] host reconnected`);

    ws.on('message', () => {});
    ws.on('close', () => {
      const r = rooms.get(code);
      if (r) {
        r.host = null;
        r.phones.forEach(p => {
          if (p.readyState === WebSocket.OPEN) p.send('status:host_disconnected');
        });
        cleanupRoom(code);
      }
    });
    return;
  }

  // ── Phone connects ────────────────────────────────────────────────────────
  const phoneMatch = url.match(/^\/phone\/([A-Z0-9]{6})$/);
  if (phoneMatch) {
    const code = phoneMatch[1].toUpperCase();
    const room = rooms.get(code);

    if (!room) {
      ws.send('error:room_not_found');
      ws.close();
      return;
    }

    room.phones.add(ws);
    ws._code = code;
    ws._role = 'phone';

    // Tell phone what device type it's controlling
    const statusMsg = room.host && room.host.readyState === WebSocket.OPEN
      ? `status:connected:${room.deviceType}`
      : `status:waiting_for_host:${room.deviceType}`;
    ws.send(statusMsg);

    console.log(`[room ${code}] phone joined — controlling ${room.deviceType}`);

    ws.on('message', (data) => {
      const r = rooms.get(code);
      if (r && r.host && r.host.readyState === WebSocket.OPEN) {
        r.host.send(data.toString());
      }
    });

    ws.on('close', () => {
      const r = rooms.get(code);
      if (r) { r.phones.delete(ws); cleanupRoom(code); }
      console.log(`[room ${code}] phone disconnected`);
    });
    return;
  }

  ws.send('error:invalid_path');
  ws.close();
});

server.listen(PORT, () => console.log(`Relay on port ${PORT}`));
