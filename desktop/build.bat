@echo off
rem Bangun LokanaDesktop.exe (satu file, tanpa jendela konsol) dengan PyInstaller.
rem Pertama kali:  python -m venv .venv  lalu  .venv\Scripts\pip install -r requirements.txt -r requirements-build.txt
cd /d "%~dp0"
copy /y ..\brand\web\icon-192.png icon.png >nul
.venv\Scripts\python -c "from PIL import Image; Image.open('icon.png').save('icon.ico', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128)])"
.venv\Scripts\pyinstaller --noconfirm --clean --onefile --noconsole --name LokanaDesktop --icon icon.ico ^
  --paths ..\protocol\tools --hidden-import lokana_link --hidden-import pystray._win32 ^
  --add-data "icon.png;." lokana_desktop.py
if errorlevel 1 (
  echo.
  echo GAGAL. Kalau LokanaDesktop.exe sedang berjalan, tutup dulu lewat tray ^(Keluar^) atau Task Manager.
  exit /b 1
)
echo.
echo Hasil: dist\LokanaDesktop.exe
