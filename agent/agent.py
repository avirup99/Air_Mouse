"""
Air Mouse Agent — Windows PC
Saves the room code locally so the phone never needs to re-scan after the first time.
Run normally : AirMouse.exe
Reset code   : AirMouse.exe --reset
"""

import asyncio
import json
import os
import sys
import threading
import webbrowser
import tempfile
import pyautogui
import websockets

RELAY_URL  = "wss://air-mouse-fb25.onrender.com"
CODE_FILE  = os.path.join(os.path.expanduser("~"), ".airmouse_code")

pyautogui.FAILSAFE = False
pyautogui.PAUSE    = 0

VK_TABLE = {
    'BACKSPACE':'backspace','TAB':'tab','ENTER':'enter','ESCAPE':'esc',
    'SPACE':'space','DELETE':'delete','UP':'up','DOWN':'down',
    'LEFT':'left','RIGHT':'right','HOME':'home','END':'end',
    'PRIOR':'pageup','NEXT':'pagedown','SNAPSHOT':'printscreen',
    'LWIN':'winleft','RWIN':'winright',
    'F1':'f1','F2':'f2','F3':'f3','F4':'f4','F5':'f5','F6':'f6',
    'F7':'f7','F8':'f8','F9':'f9','F10':'f10','F11':'f11','F12':'f12',
    'CTRL':'ctrl','ALT':'alt','SHIFT':'shift','CAPSLOCK':'capslock',
}

# ── Input handling ────────────────────────────────────────────────────────────

def handle_key(key):
    combo = key.upper()
    if '+' in combo:
        parts = combo.split('+')
        mods  = [VK_TABLE.get(p, p.lower()) for p in parts[:-1]]
        main  = VK_TABLE.get(parts[-1], parts[-1].lower())
        pyautogui.hotkey(*mods, main)
        return
    mapped = VK_TABLE.get(combo)
    if mapped:
        pyautogui.press(mapped)
    else:
        pyautogui.typewrite(key, interval=0)

def handle_command(msg):
    parts = msg.split(':', 1)
    cmd   = parts[0]
    if cmd == 'move' and len(parts) > 1:
        x, y = map(float, parts[1].split(','))
        pyautogui.moveRel(int(x), int(y), _pause=False)
    elif cmd == 'click' and len(parts) > 1:
        {'left': pyautogui.click, 'right': pyautogui.rightClick,
         'middle': pyautogui.middleClick}.get(parts[1], lambda: None)()
    elif cmd == 'scroll' and len(parts) > 1:
        pyautogui.scroll(int(parts[1]) * 3)
    elif cmd == 'key' and len(parts) > 1:
        handle_key(parts[1])

# ── Code persistence ──────────────────────────────────────────────────────────

def load_saved_code():
    try:
        with open(CODE_FILE) as f:
            return json.load(f).get('code')
    except Exception:
        return None

def save_code(code):
    try:
        with open(CODE_FILE, 'w') as f:
            json.dump({'code': code}, f)
    except Exception as e:
        print(f"[warn] Could not save code: {e}")

def delete_saved_code():
    try:
        if os.path.exists(CODE_FILE):
            os.remove(CODE_FILE)
    except Exception as e:
        print(f"[warn] Could not delete code file: {e}")

# ── Status page ───────────────────────────────────────────────────────────────

def show_status_page(code, relay_url):
    ws_url = f"{relay_url}/phone/{code}"
    html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Air Mouse — {code}</title>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&family=Syne:wght@800&display=swap" rel="stylesheet"/>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:#090c10;color:#e2e8f0;font-family:'JetBrains Mono',monospace;
min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px}}
body::before{{content:'';position:fixed;inset:0;
background-image:linear-gradient(#1e2a3a33 1px,transparent 1px),linear-gradient(90deg,#1e2a3a33 1px,transparent 1px);
background-size:48px 48px;pointer-events:none}}
.card{{background:#111620;border:1px solid #1e2a3a;border-radius:20px;padding:36px;
max-width:420px;width:100%;text-align:center;box-shadow:0 24px 80px #0008;position:relative;overflow:hidden}}
.card::before{{content:'';position:absolute;top:0;left:0;right:0;height:2px;
background:linear-gradient(90deg,#7c3aed,#00e5ff)}}
h1{{font-family:'Syne',sans-serif;font-size:2rem;font-weight:800;margin-bottom:4px}}
h1 span{{color:#00e5ff}}
.badge{{display:inline-block;background:#00e5ff1a;border:1px solid #00e5ff33;
color:#00e5ff;border-radius:100px;padding:4px 14px;font-size:11px;
letter-spacing:.15em;text-transform:uppercase;margin-bottom:20px}}
.code-box{{background:#00e5ff0f;border:1px solid #00e5ff33;border-radius:12px;padding:16px;margin-bottom:20px}}
.code-label{{font-size:10px;letter-spacing:.2em;text-transform:uppercase;color:#64748b;margin-bottom:8px}}
.code{{font-size:2.4rem;font-weight:700;letter-spacing:.2em;color:#00e5ff;text-shadow:0 0 24px #00e5ff66}}
#qr{{background:white;border-radius:12px;padding:14px;display:inline-block;margin-bottom:16px}}
.addr{{font-size:11px;color:#64748b;word-break:break-all;margin-bottom:16px}}
.btn{{background:#00e5ff1a;border:1px solid #00e5ff44;color:#00e5ff;border-radius:8px;
padding:10px 24px;font-family:inherit;font-size:12px;font-weight:700;cursor:pointer;
letter-spacing:.1em;transition:all .2s;margin:4px}}
.btn:hover{{background:#00e5ff33}}
.btn.ok{{color:#22c55e;border-color:#22c55e;background:#22c55e1a}}
.btn.red{{color:#f87171;border-color:#f8717144;background:#f871711a}}
.btn.red:hover{{background:#f8717133}}
.status{{margin-top:16px;font-size:12px;color:#64748b}}
.dot{{display:inline-block;width:7px;height:7px;border-radius:50%;background:#22c55e;
margin-right:6px;animation:blink 1.5s infinite}}
@keyframes blink{{0%,100%{{opacity:1}}50%{{opacity:.2}}}}
</style></head><body>
<div class="card">
  <h1>Air <span>Mouse</span></h1>
  <div class="badge">🖥️ PC Mode</div>
  <div class="code-box">
    <div class="code-label">Room Code</div>
    <div class="code">{code}</div>
  </div>
  <div id="qr"></div>
  <p class="addr">{ws_url}</p>
  <div>
    <button class="btn" id="cb" onclick="copy()">COPY ADDRESS</button>
    <button class="btn red" onclick="reset()">↺ RESET CODE</button>
  </div>
  <div class="status"><span class="dot"></span>Agent running · waiting for phone</div>
</div>
<script>
new QRCode(document.getElementById('qr'),{{text:'{ws_url}',width:180,height:180,
colorDark:'#000',colorLight:'#fff',correctLevel:QRCode.CorrectLevel.M}});

function copy(){{
  navigator.clipboard.writeText('{ws_url}').then(()=>{{
    const b=document.getElementById('cb');
    b.textContent='COPIED!';b.classList.add('ok');
    setTimeout(()=>{{b.textContent='COPY ADDRESS';b.classList.remove('ok')}},2000);
  }});
}}

function reset(){{
  fetch('http://localhost:7799/reset')
    .then(()=>{{ document.querySelector('.status').innerHTML='<span class="dot"></span>Restarting with new code...'; }})
    .catch(()=>{{ alert('Could not reach agent. Is it still running?'); }});
}}
</script></body></html>"""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.html', mode='w', encoding='utf-8')
    tmp.write(html)
    tmp.close()
    webbrowser.open(f'file://{tmp.name}')

# ── Local control server (for reset button) ───────────────────────────────────

from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess

class ControlHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        if self.path == '/reset':
            self.wfile.write(b'resetting')
            delete_saved_code()
            # Restart the exe/script — works for both .exe and .py
            subprocess.Popen([sys.executable if sys.executable.endswith('.py') else sys.argv[0]])
            os._exit(0)

    def log_message(self, *args): pass  # silence logs

def start_control_server():
    try:
        HTTPServer(('localhost', 7799), ControlHandler).serve_forever()
    except Exception as e:
        print(f"[warn] Control server failed: {e}")

# ── Relay communication ───────────────────────────────────────────────────────

async def register_once() -> str:
    while True:
        try:
            async with websockets.connect(f"{RELAY_URL}/register?type=pc") as ws:
                raw  = await ws.recv()
                data = json.loads(raw)
                return data['code']
        except Exception as e:
            print(f"[error] Registration failed: {e} — retrying in 5s...")
            await asyncio.sleep(5)

async def run_with_code(code: str):
    rejoin_url = f"{RELAY_URL}/rejoin/{code}?type=pc"
    while True:
        try:
            async with websockets.connect(rejoin_url) as ws:
                raw  = await ws.recv()
                data = json.loads(raw)
                print(f"[relay] Connected — Room: {data.get('code', code)}")

                async def ping_loop():
                    while True:
                        await asyncio.sleep(25)
                        try:    await ws.send('ping')
                        except: break

                asyncio.create_task(ping_loop())

                async for message in ws:
                    msg = message if isinstance(message, str) else message.decode()
                    if msg in ('ping', 'pong'): continue
                    if msg.startswith('status:'):
                        status = msg[7:]
                        if   status.startswith('phone_joined'): print("[relay] Phone connected!")
                        elif status.startswith('phone_left'):   print("[relay] Phone disconnected.")
                        else:                                   print(f"[relay] {msg}")
                    else:
                        handle_command(msg)

        except Exception as e:
            print(f"[error] {e} — retrying in 3s...")
            await asyncio.sleep(3)

# ── Entry point ───────────────────────────────────────────────────────────────

async def run():
    # Handle --reset flag
    if '--reset' in sys.argv:
        delete_saved_code()
        print("[agent] Code reset — registering fresh...")

    # Load saved code or register fresh
    code = load_saved_code()
    if code:
        print(f"[agent] Reusing saved code: {code}")
    else:
        print(f"[agent] Connecting to relay: {RELAY_URL}")
        code = await register_once()
        save_code(code)
        print(f"\n{'='*40}\n  Room Code : {code}\n{'='*40}\n")

    # Start control server (for reset button in status page)
    threading.Thread(target=start_control_server, daemon=True).start()

    # Open status page
    threading.Thread(target=show_status_page, args=(code, RELAY_URL), daemon=True).start()

    print("Waiting for phone...\n")
    await run_with_code(code)

if __name__ == '__main__':
    print("Air Mouse PC Agent starting...")
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        print("\nStopped.")