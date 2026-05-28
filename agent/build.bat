@echo off
echo Installing dependencies...
pip install pyautogui websockets pyinstaller

echo.
echo Building AirMouse.exe...
python -m PyInstaller --onefile --noconsole --name AirMouse --distpath "C:\Users\maity\Downloads\airmouse_v2\agent" agent.py

echo.
echo Done! Your exe is at:
echo C:\Users\maity\Downloads\airmouse_v2\agent\AirMouse.exe
pause
