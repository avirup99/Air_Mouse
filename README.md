# 🖱️ Air Mouse

Control your **Windows PC** or **Android TV** wirelessly from your Android phone — mouse, keyboard, TV remote, all in one app.

---

## 📥 Download

👉 Go to [**Releases**](https://github.com/YOUR_USERNAME/YOUR_REPO/releases/latest)

| File | Platform | Purpose |
|------|----------|---------|
| `AirMouse.apk` | 📱 Android Phone | Install this on your phone |
| `AirMouse.exe` | 🖥️ Windows PC | Run this on your PC |

---

## 🚀 How to Use

### Step 1 — PC Setup
1. Download and run `AirMouse.exe` on your Windows PC
2. A browser window opens showing a **QR code** and **room code**

### Step 2 — Phone Setup
1. Install `AirMouse.apk` on your Android phone
2. Open the app
3. Tap **Scan QR Code** and scan the code on your PC screen
   - Or manually enter the **room code** shown on PC

### Step 3 — Start Controlling!
- 🕹️ **Analog joystick** or **D-pad** to move the mouse
- ⌨️ **Mobile or desktop keyboard** to type
- 📺 **TV Remote mode** for Android TV
- 🖱️ Left, middle, right click buttons
- ↕️ Scroll pad

---

## ⚙️ First Time Setup

### Android (APK)
> Android blocks installs from outside the Play Store by default.

1. Open **Settings** on your phone
2. Go to **Privacy** or **Security**
3. Enable **Install from unknown sources**
4. Now open the downloaded `AirMouse.apk` and install

### Windows (EXE)
> Windows Defender may warn you since the EXE is not code-signed.

1. Click **More info** on the Windows Defender popup
2. Click **Run anyway**
3. No installation needed — it runs directly

---

## 📋 Requirements

| | Minimum |
|---|---|
| Android | 6.0 (Marshmallow) or above |
| Windows | Windows 10 or above |
| Network | Both devices need internet access |

---

## 🏗️ Project Structure

```
air-mouse/
├── relay/          # Node.js WebSocket relay server (deployed on Render)
│   └── index.js
├── mobile/         # Flutter Android app
│   └── lib/
│       ├── main.dart
│       └── ui/
├── agent/          # Windows PC agent
│   ├── agent.py
│   └── run.bat
└── README.md
```

---

## 🛠️ Self-Host / Build from Source

### Relay Server
```bash
cd relay
npm install
node index.js
```

### PC Agent (Python)
```bash
cd agent
pip install pyautogui websockets
.\run.bat
```

### Flutter App
```bash
cd mobile
flutter pub get
flutter build apk --release
```

---

## 🔧 How It Works

```
Phone  ──WebSocket──►  Relay Server  ──WebSocket──►  PC Agent
         (commands)    (Render cloud)   (executes mouse/keyboard)
```

The relay server sits in the cloud and passes commands from your phone to your PC. No direct connection between devices needed — works over the internet.

---

### Future and current updates 

The android tv support will soon be released.
the tv_remote_ui.dart is updated where the apk is build is built on its older version, it should run fine even if you build with the updated version.


## 📄 License

MIT — free to use, modify and distribute.
