const WebSocket = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;

// rooms: { roomCode -> { pc: WebSocket|null, phones: Set<WebSocket> } }
const rooms = new Map();

function getOrCreateRoom(code) {
  if (!rooms.has(code)) {
    rooms.set(code, { pc: null, phones: new Set() });
  }
  return rooms.get(code);
}

function cleanupRoom(code) {
  const room = rooms.get(code);
  if (!room) return;
  if (!room.pc && room.phones.size === 0) {
    rooms.delete(code);
    console.log(`[room ${code}] deleted (empty)`);
  }
}

// Generate a random 6-char alphanumeric room code
function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

function makeUniqueCode() {
  let code;
  do { code = generateCode(); } while (rooms.has(code));
  return code;
}

// ── HTTP server (health check + Render keep-alive) ────────────────────────
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', rooms: rooms.size }));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Air Mouse Relay Server');
});

// ── WebSocket server ──────────────────────────────────────────────────────
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
  // URL format:
  //   /register        → PC agent registers, gets a room code back
  //   /pc/<code>       → PC agent joins a specific room (reconnect)
  //   /phone/<code>    → Phone joins a room
  const url = req.url || '/';
  console.log(`[ws] new connection: ${url}`);

  // ── PC registers (new session) ────────────────────────────────────────
  if (url === '/register') {
    const code = makeUniqueCode();
    const room = getOrCreateRoom(code);
    room.pc = ws;
    ws._role = 'pc';
    ws._code = code;

    ws.send(JSON.stringify({ type: 'registered', code }));
    console.log(`[room ${code}] PC registered`);

    ws.on('message', () => {}); // PC doesn't send anything upstream
    ws.on('close', () => {
      const r = rooms.get(code);
      if (r) {
        r.pc = null;
        // Notify all phones
        r.phones.forEach(phone => {
          if (phone.readyState === WebSocket.OPEN) {
            phone.send('status:pc_disconnected');
          }
        });
        cleanupRoom(code);
      }
      console.log(`[room ${code}] PC disconnected`);
    });
    return;
  }

  // ── PC reconnects to existing code ───────────────────────────────────
  const pcMatch = url.match(/^\/pc\/([A-Z0-9]{6})$/);
  if (pcMatch) {
    const code = pcMatch[1];
    const room = getOrCreateRoom(code);
    room.pc = ws;
    ws._role = 'pc';
    ws._code = code;

    ws.send(JSON.stringify({ type: 'registered', code }));
    console.log(`[room ${code}] PC reconnected`);

    // Notify waiting phones
    room.phones.forEach(phone => {
      if (phone.readyState === WebSocket.OPEN) {
        phone.send('status:connected');
      }
    });

    ws.on('message', () => {});
    ws.on('close', () => {
      const r = rooms.get(code);
      if (r) {
        r.pc = null;
        r.phones.forEach(phone => {
          if (phone.readyState === WebSocket.OPEN) {
            phone.send('status:pc_disconnected');
          }
        });
        cleanupRoom(code);
      }
      console.log(`[room ${code}] PC disconnected`);
    });
    return;
  }

  // ── Phone connects ────────────────────────────────────────────────────
  const phoneMatch = url.match(/^\/phone\/([A-Z0-9]{6})$/);
  if (phoneMatch) {
    const code = phoneMatch[1].toUpperCase();
    const room = rooms.get(code);

    if (!room) {
      ws.send('error:room_not_found');
      ws.close();
      console.log(`[room ${code}] phone tried to join — room not found`);
      return;
    }

    room.phones.add(ws);
    ws._role = 'phone';
    ws._code = code;

    if (room.pc && room.pc.readyState === WebSocket.OPEN) {
      ws.send('status:connected');
    } else {
      ws.send('status:waiting_for_pc');
    }

    console.log(`[room ${code}] phone joined (${room.phones.size} phones)`);

    ws.on('message', (data) => {
      // Forward command to PC
      const r = rooms.get(code);
      if (r && r.pc && r.pc.readyState === WebSocket.OPEN) {
        r.pc.send(data.toString());
      }
    });

    ws.on('close', () => {
      const r = rooms.get(code);
      if (r) {
        r.phones.delete(ws);
        cleanupRoom(code);
      }
      console.log(`[room ${code}] phone disconnected`);
    });
    return;
  }

  // Unknown path
  ws.send('error:invalid_path');
  ws.close();
});

server.listen(PORT, () => {
  console.log(`Air Mouse relay running on port ${PORT}`);
});
