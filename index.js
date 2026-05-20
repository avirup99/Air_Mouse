const WebSocket = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;

// rooms: { code -> { host: WebSocket|null, deviceType: 'pc'|'tv', phones: Set<WebSocket>, cleanupTimer: Timeout|null } }
const rooms = new Map();

// How long to keep a room alive after the host disconnects (ms).
// Gives the PC agent time to reconnect without losing the code.
const ROOM_LINGER_MS = 30_000;

function getOrCreateRoom(code, deviceType = 'pc') {
  if (!rooms.has(code)) {
    rooms.set(code, { host: null, deviceType, phones: new Set(), cleanupTimer: null });
  }
  return rooms.get(code);
}

// Schedule room deletion after ROOM_LINGER_MS, unless host rejoins first.
function scheduleCleanup(code) {
  const room = rooms.get(code);
  if (!room) return;
  // Cancel any existing timer so we don't double-schedule.
  if (room.cleanupTimer) clearTimeout(room.cleanupTimer);
  room.cleanupTimer = setTimeout(() => {
    const r = rooms.get(code);
    if (r && !r.host && r.phones.size === 0) {
      rooms.delete(code);
      console.log(`[room ${code}] deleted after linger timeout`);
    }
  }, ROOM_LINGER_MS);
}

// Cancel a pending cleanup (host came back in time).
function cancelCleanup(code) {
  const room = rooms.get(code);
  if (room && room.cleanupTimer) {
    clearTimeout(room.cleanupTimer);
    room.cleanupTimer = null;
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
  // /register?type=pc[&code=XXXXXX]
  // If ?code= is provided and the room still exists, the host REJOINS it.
  // Otherwise a fresh code is issued.
  if (url.startsWith('/register')) {
    const params = new URLSearchParams(url.split('?')[1] || '');
    const deviceType = params.get('type') === 'tv' ? 'tv' : 'pc';
    const requestedCode = (params.get('code') || '').toUpperCase();

    let code;
    let rejoining = false;

    if (requestedCode && rooms.has(requestedCode)) {
      // Room still alive — host is reconnecting, reuse the same code.
      code = requestedCode;
      rejoining = true;
    } else {
      // Fresh registration — generate a new unique code.
      code = makeUniqueCode();
    }

    const room = getOrCreateRoom(code, deviceType);
    room.host = ws;
    room.deviceType = deviceType;
    ws._code = code;
    ws._role = 'host';

    // Cancel any pending room-deletion timer.
    cancelCleanup(code);

    ws.send(JSON.stringify({ type: 'registered', code, deviceType }));

    if (rejoining) {
      // Tell waiting phones the host is back.
      room.phones.forEach(p => {
        if (p.readyState === WebSocket.OPEN)
          p.send(`status:connected:${deviceType}`);
      });
      console.log(`[room ${code}] ${deviceType} REJOINED`);
    } else {
      console.log(`[room ${code}] ${deviceType} registered`);
    }

    ws.on('message', (data) => {
      // Relay host→phone messages (e.g. status broadcasts) if ever needed.
      // Currently the host doesn't send anything meaningful.
    });

    ws.on('close', () => {
      const r = rooms.get(code);
      if (r) {
        r.host = null;
        r.phones.forEach(p => {
          if (p.readyState === WebSocket.OPEN)
            p.send('status:host_disconnected');
        });
        // Don't delete immediately — give the agent time to reconnect.
        scheduleCleanup(code);
      }
      console.log(`[room ${code}] host disconnected — room kept for ${ROOM_LINGER_MS / 1000}s`);
    });
    return;
  }

  // ── Phone connects ────────────────────────────────────────────────────────
  const phoneMatch = url.match(/^\/phone\/([A-Z0-9]{6})$/i);
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

    const statusMsg = room.host && room.host.readyState === WebSocket.OPEN
      ? `status:connected:${room.deviceType}`
      : `status:waiting_for_host:${room.deviceType}`;
    ws.send(statusMsg);

    console.log(`[room ${code}] phone joined — controlling ${room.deviceType}`);

    ws.on('message', (data) => {
      const msg = data.toString();
      if (msg === 'ping') { ws.send('pong'); return; }
      const r = rooms.get(code);
      if (r && r.host && r.host.readyState === WebSocket.OPEN) {
        r.host.send(msg);
      }
    });

    ws.on('close', () => {
      const r = rooms.get(code);
      if (r) {
        r.phones.delete(ws);
        // Only schedule cleanup if host is also gone.
        if (!r.host) scheduleCleanup(code);
      }
      console.log(`[room ${code}] phone disconnected`);
    });
    return;
  }

  ws.send('error:invalid_path');
  ws.close();
});

server.listen(PORT, () => console.log(`Relay on port ${PORT}`));
