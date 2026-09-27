@echo off
cd /d "%~dp0"
python -m pip install -r requirements.txt
python -c "from waitress import serve; from app import app; serve(app, host='0.0.0.0', port=int(__import__('os').environ.get('PORT','5000')))"
