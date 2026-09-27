import os
import sqlite3
from datetime import datetime, timezone
from werkzeug.security import generate_password_hash

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.environ.get("VIDSHARE_DB_PATH", os.path.join(BASE_DIR, "vidshare.db"))
USERNAME = os.environ.get("VIDSHARE_ADMIN_USERNAME", "최연욱").strip()
PASSWORD = os.environ.get("VIDSHARE_ADMIN_PASSWORD", "151013")

conn = sqlite3.connect(DB_PATH)
conn.execute("PRAGMA foreign_keys = ON")
conn.execute("""
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    bio TEXT DEFAULT '',
    avatar_filename TEXT DEFAULT '',
    is_admin INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
)
""")
row = conn.execute("SELECT id FROM users WHERE username = ?", (USERNAME,)).fetchone()
now = datetime.now(timezone.utc).isoformat()
if row:
    conn.execute("UPDATE users SET is_admin = 1, password_hash = ? WHERE id = ?",
                 (generate_password_hash(PASSWORD), row[0]))
else:
    conn.execute("INSERT INTO users(username, password_hash, created_at, is_admin) VALUES (?, ?, ?, 1)",
                 (USERNAME, generate_password_hash(PASSWORD), now))
conn.commit()
conn.close()
print(f"관리자 계정 준비 완료: {USERNAME}")
