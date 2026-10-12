from flask import Flask, render_template, request, redirect, url_for, session, flash, abort, send_from_directory
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
import sqlite3
import os
import uuid
import hashlib
import secrets
import subprocess
import shutil
from datetime import datetime, timezone

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
try:
    from asset_bundle import ensure_assets
    ensure_assets(BASE_DIR)
except Exception:
    # If the normal folders are present, continue; otherwise Flask will surface the real error.
    pass
DATA_DIR = os.environ.get('VIDSHARE_DATA_DIR', BASE_DIR)
DB_PATH = os.environ.get('VIDSHARE_DB_PATH', os.path.join(DATA_DIR, 'vidshare.db'))
UPLOAD_DIR = os.environ.get('VIDSHARE_UPLOAD_DIR', os.path.join(DATA_DIR, 'uploads'))
THUMB_DIR = os.environ.get('VIDSHARE_THUMB_DIR', os.path.join(DATA_DIR, 'thumbnails'))
ALLOWED_EXTENSIONS = {'mp4', 'webm', 'ogg', 'mov'}
MAX_UPLOAD_MB = int(os.environ.get('VIDSHARE_MAX_UPLOAD_MB', '500'))
ADMIN_USERNAME = os.environ.get('VIDSHARE_ADMIN_USERNAME', '최연욱').strip()
ADMIN_PASSWORD = os.environ.get('VIDSHARE_ADMIN_PASSWORD', '151013')

app = Flask(
    __name__,
    template_folder=os.path.join(BASE_DIR, 'templates'),
    static_folder=os.path.join(BASE_DIR, 'static'),
)
app.secret_key = os.environ.get('VIDSHARE_SECRET') or secrets.token_hex(32)
app.config['MAX_CONTENT_LENGTH'] = MAX_UPLOAD_MB * 1024 * 1024
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
app.config['SESSION_COOKIE_SECURE'] = os.environ.get('VIDSHARE_HTTPS', '').lower() == 'true'
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(THUMB_DIR, exist_ok=True)


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA foreign_keys = ON')
    conn.execute('PRAGMA busy_timeout = 30000')
    return conn


def column_exists(conn, table, column):
    return any(r['name'] == column for r in conn.execute(f'PRAGMA table_info({table})').fetchall())


def init_db():
    conn = get_db()
    conn.executescript('''
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        bio TEXT DEFAULT '',
        avatar_filename TEXT DEFAULT '',
        is_admin INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS videos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT DEFAULT '',
        filename TEXT NOT NULL,
        thumbnail_filename TEXT DEFAULT '',
        views INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS likes (
        user_id INTEGER NOT NULL,
        video_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY(user_id, video_id),
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(video_id) REFERENCES videos(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS subscriptions (
        subscriber_id INTEGER NOT NULL,
        channel_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY(subscriber_id, channel_id),
        CHECK(subscriber_id <> channel_id),
        FOREIGN KEY(subscriber_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(channel_id) REFERENCES users(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS comments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        video_id INTEGER NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(video_id) REFERENCES videos(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS comment_likes (
        user_id INTEGER NOT NULL,
        comment_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY(user_id, comment_id),
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(comment_id) REFERENCES comments(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS views (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_id INTEGER NOT NULL,
        viewer_key TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(video_id, viewer_key),
        FOREIGN KEY(video_id) REFERENCES videos(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reporter_id INTEGER,
        video_id INTEGER,
        comment_id INTEGER,
        reason TEXT NOT NULL,
        details TEXT DEFAULT '',
        status TEXT NOT NULL DEFAULT 'open',
        created_at TEXT NOT NULL,
        FOREIGN KEY(reporter_id) REFERENCES users(id) ON DELETE SET NULL,
        FOREIGN KEY(video_id) REFERENCES videos(id) ON DELETE CASCADE,
        FOREIGN KEY(comment_id) REFERENCES comments(id) ON DELETE CASCADE
    );
    ''')

    # Gunicorn can import app.py in multiple workers at the same time.
    # Serialize migrations/admin bootstrap so two workers cannot create the
    # same unique username concurrently. SQLite will wait up to busy_timeout.
    conn.execute('BEGIN IMMEDIATE')

    # Migration for databases created by the older starter version.
    if not column_exists(conn, 'users', 'bio'):
        conn.execute("ALTER TABLE users ADD COLUMN bio TEXT DEFAULT ''")
    if not column_exists(conn, 'users', 'avatar_filename'):
        conn.execute("ALTER TABLE users ADD COLUMN avatar_filename TEXT DEFAULT ''")
    if not column_exists(conn, 'users', 'is_admin'):
        conn.execute("ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0")
    if not column_exists(conn, 'videos', 'thumbnail_filename'):
        conn.execute("ALTER TABLE videos ADD COLUMN thumbnail_filename TEXT DEFAULT ''")
    if not column_exists(conn, 'videos', 'updated_at'):
        conn.execute("ALTER TABLE videos ADD COLUMN updated_at TEXT NOT NULL DEFAULT ''")
        conn.execute("UPDATE videos SET updated_at = created_at WHERE updated_at = ''")

    # 기본 관리자 계정 생성/보정
    # INSERT OR IGNORE + UPDATE를 사용해 여러 Gunicorn worker가 동시에
    # 부팅되어도 UNIQUE(username) 충돌이 발생하지 않도록 한다.
    if ADMIN_USERNAME and ADMIN_PASSWORD:
        password_hash = generate_password_hash(ADMIN_PASSWORD)
        conn.execute(
            '''INSERT OR IGNORE INTO users(username, password_hash, created_at, is_admin)
               VALUES (?, ?, ?, 1)''',
            (ADMIN_USERNAME, password_hash, now_iso())
        )
        conn.execute(
            'UPDATE users SET is_admin = 1, password_hash = ? WHERE username = ?',
            (password_hash, ADMIN_USERNAME)
        )

    conn.commit()
    conn.close()


def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def video_path(filename):
    return os.path.join(UPLOAD_DIR, filename)


def thumbnail_path(filename):
    return os.path.join(THUMB_DIR, filename)


def create_thumbnail(video_file, thumbnail_file):
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        return False
    try:
        subprocess.run([
            ffmpeg, '-y', '-ss', '00:00:01', '-i', video_file,
            '-frames:v', '1', '-vf', 'scale=640:-2', thumbnail_file
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        return os.path.exists(thumbnail_file)
    except (subprocess.SubprocessError, OSError):
        return False


def current_user_id():
    return session.get('user_id')


def current_user():
    uid = current_user_id()
    if not uid:
        return None
    conn = get_db()
    user = conn.execute('SELECT * FROM users WHERE id = ?', (uid,)).fetchone()
    conn.close()
    return user


def csrf_token():
    if 'csrf_token' not in session:
        session['csrf_token'] = secrets.token_urlsafe(32)
    return session['csrf_token']


def validate_csrf():
    sent = request.form.get('csrf_token') or request.headers.get('X-CSRF-Token')
    if not sent or not secrets.compare_digest(sent, session.get('csrf_token', '')):
        abort(400, description='잘못된 요청입니다. 페이지를 새로고침한 뒤 다시 시도해주세요.')


@app.context_processor
def inject_globals():
    user = current_user()
    return {
        'logged_in': user is not None,
        'current_user': user,
        'csrf_token': csrf_token,
    }


def algorithm_feed(user_id=None, limit=50):
    conn = get_db()
    rows = conn.execute('''
        SELECT v.*, u.username,
               (SELECT COUNT(*) FROM likes l WHERE l.video_id = v.id) AS like_count,
               (SELECT COUNT(*) FROM comments c WHERE c.video_id = v.id) AS comment_count,
               CASE WHEN ? IS NOT NULL AND EXISTS (
                   SELECT 1 FROM subscriptions s
                   WHERE s.subscriber_id = ? AND s.channel_id = v.user_id
               ) THEN 1 ELSE 0 END AS subscribed_creator
        FROM videos v
        JOIN users u ON u.id = v.user_id
        ORDER BY (
            subscribed_creator * 1000 +
            like_count * 7 +
            comment_count * 3 +
            MIN(v.views, 500) * 0.25 +
            MAX(0, 72 - (julianday('now') - julianday(v.created_at)) * 24) * 0.8
        ) DESC, v.id DESC
        LIMIT ?
    ''', (user_id, user_id, limit)).fetchall()
    conn.close()
    return rows


def viewer_key():
    uid = current_user_id()
    if uid:
        return f'user:{uid}'
    raw = f"{request.remote_addr or 'unknown'}|{request.headers.get('User-Agent', '')}|{app.secret_key}"
    return 'anon:' + hashlib.sha256(raw.encode('utf-8')).hexdigest()


def require_login(message='로그인 후 이용할 수 있습니다.'):
    # 세션에 남아 있는 오래된 user_id를 그대로 믿지 않고 실제 DB의 사용자인지 확인한다.
    # 예: DB를 삭제/재생성한 뒤 예전 세션으로 업로드하면 FK 오류가 날 수 있다.
    user = current_user()
    if not user:
        session.clear()
        flash(message)
        return redirect(url_for('login', next=request.path))
    return None


def require_admin():
    user = current_user()
    if not user or not user['is_admin']:
        abort(403)
    return user


def get_video(conn, video_id):
    return conn.execute('''
        SELECT v.*, u.username,
               (SELECT COUNT(*) FROM likes l WHERE l.video_id = v.id) AS like_count,
               (SELECT COUNT(*) FROM subscriptions s WHERE s.channel_id = v.user_id) AS subscriber_count
        FROM videos v JOIN users u ON u.id = v.user_id
        WHERE v.id = ?
    ''', (video_id,)).fetchone()


def owns_video(video_id):
    conn = get_db()
    row = conn.execute('SELECT user_id FROM videos WHERE id = ?', (video_id,)).fetchone()
    conn.close()
    return bool(row and row['user_id'] == current_user_id())


@app.route('/')
def index():
    videos = algorithm_feed(current_user_id())
    return render_template('index.html', videos=videos)


@app.route('/subscriptions')
def subscriptions_feed():
    guard = require_login('구독 피드는 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    conn = get_db()
    videos = conn.execute('''
        SELECT v.*, u.username,
               (SELECT COUNT(*) FROM likes l WHERE l.video_id = v.id) AS like_count,
               (SELECT COUNT(*) FROM comments c WHERE c.video_id = v.id) AS comment_count
        FROM videos v
        JOIN users u ON u.id = v.user_id
        JOIN subscriptions s ON s.channel_id = v.user_id
        WHERE s.subscriber_id = ?
        ORDER BY v.created_at DESC
        LIMIT 100
    ''', (current_user_id(),)).fetchall()
    conn.close()
    return render_template('subscriptions.html', videos=videos)


@app.route('/register', methods=['GET', 'POST'])
def register():
    if current_user():
        return redirect(url_for('index'))
    if request.method == 'POST':
        validate_csrf()
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        if len(username) < 2 or len(username) > 30:
            flash('닉네임은 2~30자여야 합니다.')
            return render_template('register.html')
        if len(password) < 8:
            flash('비밀번호는 8자 이상이어야 합니다.')
            return render_template('register.html')
        conn = get_db()
        try:
            conn.execute(
                'INSERT INTO users(username, password_hash, created_at) VALUES (?, ?, ?)',
                (username, generate_password_hash(password), now_iso())
            )
            conn.commit()
        except sqlite3.IntegrityError:
            conn.close()
            flash('이미 사용 중인 닉네임입니다.')
            return render_template('register.html')
        conn.close()
        flash('회원가입이 완료되었습니다. 로그인해주세요.')
        return redirect(url_for('login'))
    return render_template('register.html')


@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user():
        return redirect(url_for('index'))
    if request.method == 'POST':
        validate_csrf()
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        conn = get_db()
        user = conn.execute('SELECT * FROM users WHERE username = ?', (username,)).fetchone()
        conn.close()
        if not user or not check_password_hash(user['password_hash'], password):
            flash('닉네임 또는 비밀번호가 올바르지 않습니다.')
            return render_template('login.html')
        session.clear()
        session['user_id'] = user['id']
        session['username'] = user['username']
        session['csrf_token'] = secrets.token_urlsafe(32)
        next_url = request.args.get('next', '')
        return redirect(next_url if next_url.startswith('/') else url_for('index'))
    return render_template('login.html')


@app.route('/logout', methods=['POST'])
def logout():
    validate_csrf()
    session.clear()
    return redirect(url_for('index'))


@app.route('/upload', methods=['GET', 'POST'])
def upload():
    guard = require_login('영상 업로드는 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    if request.method == 'POST':
        validate_csrf()
        title = request.form.get('title', '').strip()
        description = request.form.get('description', '').strip()
        video = request.files.get('video')
        if not title:
            flash('영상 제목을 입력해주세요.')
            return render_template('upload.html')
        if not video or not video.filename:
            flash('영상 파일을 선택해주세요.')
            return render_template('upload.html')
        if not allowed_file(video.filename):
            flash('지원 파일: MP4, WEBM, OGG, MOV')
            return render_template('upload.html')

        original = secure_filename(video.filename)
        if not original or '.' not in original:
            flash('올바른 영상 파일이 아닙니다.')
            return render_template('upload.html')
        ext = original.rsplit('.', 1)[1].lower()
        filename = f'{uuid.uuid4().hex}.{ext}'
        path = video_path(filename)
        video.save(path)

        thumb_name = f'{uuid.uuid4().hex}.jpg'
        thumb_path = thumbnail_path(thumb_name)
        has_thumb = create_thumbnail(path, thumb_path)
        if not has_thumb:
            thumb_name = ''

        # 로그인 사용자를 DB에서 다시 확인해 FK에 유효한 users.id만 저장한다.
        user = current_user()
        if not user:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
            if thumb_name:
                try:
                    os.remove(thumb_path)
                except FileNotFoundError:
                    pass
            session.clear()
            flash('로그인 정보가 만료되었습니다. 다시 로그인해주세요.')
            return redirect(url_for('login', next=url_for('upload')))

        timestamp = now_iso()
        conn = get_db()
        try:
            cursor = conn.execute('''
                INSERT INTO videos(user_id, title, description, filename, thumbnail_filename, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (user['id'], title[:200], description[:5000], filename, thumb_name, timestamp, timestamp))
            conn.commit()
            video_id = cursor.lastrowid
        except sqlite3.IntegrityError:
            conn.rollback()
            conn.close()
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
            if thumb_name:
                try:
                    os.remove(thumb_path)
                except FileNotFoundError:
                    pass
            flash('영상 정보를 저장하지 못했습니다. 로그인 상태를 확인한 뒤 다시 시도해주세요.')
            return render_template('upload.html'), 400
        finally:
            try:
                conn.close()
            except Exception:
                pass
        return redirect(url_for('watch', video_id=video_id))
    return render_template('upload.html')


@app.route('/watch/<int:video_id>', methods=['GET', 'POST'])
def watch(video_id):
    conn = get_db()
    video = get_video(conn, video_id)
    if not video:
        conn.close()
        abort(404)

    if request.method == 'POST':
        guard = require_login('댓글 작성은 로그인 후 이용할 수 있습니다.')
        if guard:
            conn.close()
            return guard
        validate_csrf()
        body = request.form.get('body', '').strip()
        if body:
            conn.execute('INSERT INTO comments(user_id, video_id, body, created_at) VALUES (?, ?, ?, ?)',
                         (current_user_id(), video_id, body[:1000], now_iso()))
            conn.commit()

    # One counted view per viewer key, rather than every page refresh.
    key = viewer_key()
    existing_view = conn.execute('SELECT 1 FROM views WHERE video_id = ? AND viewer_key = ?',
                                 (video_id, key)).fetchone()
    if not existing_view:
        conn.execute('INSERT INTO views(video_id, viewer_key, created_at) VALUES (?, ?, ?)',
                     (video_id, key, now_iso()))
        conn.execute('UPDATE videos SET views = views + 1 WHERE id = ?', (video_id,))
        conn.commit()
        video = get_video(conn, video_id)

    viewer_id = current_user_id()
    liked = bool(viewer_id and conn.execute(
        'SELECT 1 FROM likes WHERE user_id = ? AND video_id = ?', (viewer_id, video_id)
    ).fetchone())
    subscribed = bool(viewer_id and viewer_id != video['user_id'] and conn.execute(
        'SELECT 1 FROM subscriptions WHERE subscriber_id = ? AND channel_id = ?',
        (viewer_id, video['user_id'])
    ).fetchone())
    comments = conn.execute('''
        SELECT c.*, u.username,
               (SELECT COUNT(*) FROM comment_likes cl WHERE cl.comment_id = c.id) AS like_count,
               CASE WHEN ? IS NOT NULL AND EXISTS (
                   SELECT 1 FROM comment_likes cl2 WHERE cl2.comment_id = c.id AND cl2.user_id = ?
               ) THEN 1 ELSE 0 END AS liked_by_me
        FROM comments c JOIN users u ON u.id = c.user_id
        WHERE c.video_id = ? ORDER BY c.id DESC
    ''', (viewer_id, viewer_id, video_id)).fetchall()
    recommendations = [v for v in algorithm_feed(viewer_id, 13) if v['id'] != video_id][:12]
    conn.close()
    return render_template('watch.html', video=video, liked=liked,
                           subscribed=subscribed, comments=comments,
                           recommendations=recommendations)


@app.route('/like/<int:video_id>', methods=['POST'])
def toggle_like(video_id):
    guard = require_login('좋아요는 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    validate_csrf()
    conn = get_db()
    if not conn.execute('SELECT 1 FROM videos WHERE id = ?', (video_id,)).fetchone():
        conn.close(); abort(404)
    existing = conn.execute('SELECT 1 FROM likes WHERE user_id = ? AND video_id = ?',
                            (current_user_id(), video_id)).fetchone()
    if existing:
        conn.execute('DELETE FROM likes WHERE user_id = ? AND video_id = ?',
                     (current_user_id(), video_id))
    else:
        conn.execute('INSERT INTO likes(user_id, video_id, created_at) VALUES (?, ?, ?)',
                     (current_user_id(), video_id, now_iso()))
    conn.commit(); conn.close()
    return redirect(request.referrer or url_for('watch', video_id=video_id))


@app.route('/subscribe/<int:channel_id>', methods=['POST'])
def toggle_subscribe(channel_id):
    guard = require_login('구독은 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    validate_csrf()
    if current_user_id() == channel_id:
        flash('자기 자신은 구독할 수 없습니다.')
        return redirect(request.referrer or url_for('index'))
    conn = get_db()
    if not conn.execute('SELECT 1 FROM users WHERE id = ?', (channel_id,)).fetchone():
        conn.close(); abort(404)
    exists = conn.execute('SELECT 1 FROM subscriptions WHERE subscriber_id = ? AND channel_id = ?',
                          (current_user_id(), channel_id)).fetchone()
    if exists:
        conn.execute('DELETE FROM subscriptions WHERE subscriber_id = ? AND channel_id = ?',
                     (current_user_id(), channel_id))
    else:
        conn.execute('INSERT INTO subscriptions(subscriber_id, channel_id, created_at) VALUES (?, ?, ?)',
                     (current_user_id(), channel_id, now_iso()))
    conn.commit(); conn.close()
    return redirect(request.referrer or url_for('index'))


@app.route('/comment/<int:comment_id>/like', methods=['POST'])
def toggle_comment_like(comment_id):
    guard = require_login('댓글 좋아요는 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    validate_csrf()
    conn = get_db()
    if not conn.execute('SELECT 1 FROM comments WHERE id = ?', (comment_id,)).fetchone():
        conn.close(); abort(404)
    existing = conn.execute('SELECT 1 FROM comment_likes WHERE user_id = ? AND comment_id = ?',
                            (current_user_id(), comment_id)).fetchone()
    if existing:
        conn.execute('DELETE FROM comment_likes WHERE user_id = ? AND comment_id = ?',
                     (current_user_id(), comment_id))
    else:
        conn.execute('INSERT INTO comment_likes(user_id, comment_id, created_at) VALUES (?, ?, ?)',
                     (current_user_id(), comment_id, now_iso()))
    conn.commit()
    video_id = conn.execute('SELECT video_id FROM comments WHERE id = ?', (comment_id,)).fetchone()['video_id']
    conn.close()
    return redirect(url_for('watch', video_id=video_id) + '#comments')


@app.route('/channel/<int:user_id>')
def channel(user_id):
    conn = get_db()
    user = conn.execute('SELECT id, username, bio, avatar_filename, created_at, is_admin FROM users WHERE id = ?', (user_id,)).fetchone()
    if not user:
        conn.close(); abort(404)
    videos = conn.execute('''
        SELECT v.*, (SELECT COUNT(*) FROM likes l WHERE l.video_id = v.id) AS like_count
        FROM videos v WHERE v.user_id = ? ORDER BY v.id DESC
    ''', (user_id,)).fetchall()
    subscriber_count = conn.execute('SELECT COUNT(*) FROM subscriptions WHERE channel_id = ?', (user_id,)).fetchone()[0]
    subscribed = bool(current_user_id() and current_user_id() != user_id and conn.execute(
        'SELECT 1 FROM subscriptions WHERE subscriber_id = ? AND channel_id = ?',
        (current_user_id(), user_id)
    ).fetchone())
    conn.close()
    return render_template('channel.html', channel=user, videos=videos,
                           subscriber_count=subscriber_count, subscribed=subscribed)


@app.route('/profile/edit', methods=['GET', 'POST'])
def edit_profile():
    guard = require_login('프로필 편집은 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    conn = get_db()
    if request.method == 'POST':
        validate_csrf()
        bio = request.form.get('bio', '').strip()[:500]
        username = request.form.get('username', '').strip()
        if len(username) < 2 or len(username) > 30:
            conn.close(); flash('닉네임은 2~30자여야 합니다.'); return render_template('profile_edit.html', user=current_user())
        try:
            conn.execute('UPDATE users SET username = ?, bio = ? WHERE id = ?', (username, bio, current_user_id()))
            conn.commit()
            session['username'] = username
        except sqlite3.IntegrityError:
            conn.close(); flash('이미 사용 중인 닉네임입니다.'); return render_template('profile_edit.html', user=current_user())
        conn.close()
        flash('프로필이 저장되었습니다.')
        return redirect(url_for('channel', user_id=current_user_id()))
    user = conn.execute('SELECT * FROM users WHERE id = ?', (current_user_id(),)).fetchone()
    conn.close()
    return render_template('profile_edit.html', user=user)


@app.route('/video/<int:video_id>/edit', methods=['GET', 'POST'])
def edit_video(video_id):
    guard = require_login('영상 수정은 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    conn = get_db()
    video = conn.execute('SELECT * FROM videos WHERE id = ?', (video_id,)).fetchone()
    if not video:
        conn.close(); abort(404)
    if video['user_id'] != current_user_id() and not current_user()['is_admin']:
        conn.close(); abort(403)
    if request.method == 'POST':
        validate_csrf()
        title = request.form.get('title', '').strip()
        description = request.form.get('description', '').strip()
        if not title:
            conn.close(); flash('제목을 입력해주세요.'); return render_template('edit_video.html', video=video)
        conn.execute('UPDATE videos SET title = ?, description = ?, updated_at = ? WHERE id = ?',
                     (title[:200], description[:5000], now_iso(), video_id))
        conn.commit(); conn.close()
        flash('영상 정보가 수정되었습니다.')
        return redirect(url_for('watch', video_id=video_id))
    conn.close()
    return render_template('edit_video.html', video=video)


@app.route('/video/<int:video_id>/delete', methods=['POST'])
def delete_video(video_id):
    guard = require_login('영상 삭제는 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    validate_csrf()
    conn = get_db()
    video = conn.execute('SELECT * FROM videos WHERE id = ?', (video_id,)).fetchone()
    if not video:
        conn.close(); abort(404)
    user = current_user()
    if video['user_id'] != current_user_id() and not user['is_admin']:
        conn.close(); abort(403)
    conn.execute('DELETE FROM videos WHERE id = ?', (video_id,))
    conn.commit(); conn.close()
    for filename, folder in [(video['filename'], UPLOAD_DIR), (video['thumbnail_filename'], THUMB_DIR)]:
        if filename:
            try: os.remove(os.path.join(folder, filename))
            except FileNotFoundError: pass
    flash('영상이 삭제되었습니다.')
    return redirect(url_for('channel', user_id=user['id']))


@app.route('/report/video/<int:video_id>', methods=['POST'])
def report_video(video_id):
    guard = require_login('신고는 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    validate_csrf()
    reason = request.form.get('reason', '').strip()[:100]
    details = request.form.get('details', '').strip()[:1000]
    if not reason:
        flash('신고 사유를 선택해주세요.')
        return redirect(url_for('watch', video_id=video_id))
    conn = get_db()
    if not conn.execute('SELECT 1 FROM videos WHERE id = ?', (video_id,)).fetchone():
        conn.close(); abort(404)
    conn.execute('INSERT INTO reports(reporter_id, video_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?)',
                 (current_user_id(), video_id, reason, details, now_iso()))
    conn.commit(); conn.close()
    flash('신고가 접수되었습니다. 관리자 검토 후 처리됩니다.')
    return redirect(url_for('watch', video_id=video_id))


@app.route('/report/comment/<int:comment_id>', methods=['POST'])
def report_comment(comment_id):
    guard = require_login('신고는 로그인 후 이용할 수 있습니다.')
    if guard:
        return guard
    validate_csrf()
    reason = request.form.get('reason', '').strip()[:100]
    details = request.form.get('details', '').strip()[:1000]
    if not reason:
        flash('신고 사유를 선택해주세요.')
        return redirect(request.referrer or url_for('index'))
    conn = get_db()
    comment = conn.execute('SELECT * FROM comments WHERE id = ?', (comment_id,)).fetchone()
    if not comment:
        conn.close(); abort(404)
    conn.execute('INSERT INTO reports(reporter_id, comment_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?)',
                 (current_user_id(), comment_id, reason, details, now_iso()))
    conn.commit(); conn.close()
    flash('댓글 신고가 접수되었습니다.')
    return redirect(url_for('watch', video_id=comment['video_id']) + '#comments')


@app.route('/search')
def search():
    q = request.args.get('q', '').strip()
    conn = get_db()
    if q:
        videos = conn.execute('''
            SELECT v.*, u.username,
                   (SELECT COUNT(*) FROM likes l WHERE l.video_id = v.id) AS like_count,
                   (SELECT COUNT(*) FROM comments c WHERE c.video_id = v.id) AS comment_count
            FROM videos v JOIN users u ON u.id = v.user_id
            WHERE v.title LIKE ? OR v.description LIKE ? OR u.username LIKE ?
            ORDER BY v.id DESC LIMIT 50
        ''', (f'%{q}%', f'%{q}%', f'%{q}%')).fetchall()
        channels = conn.execute('''
            SELECT u.id, u.username, u.bio, u.avatar_filename, u.created_at, u.is_admin,
                   (SELECT COUNT(*) FROM subscriptions s WHERE s.channel_id = u.id) AS subscriber_count,
                   (SELECT COUNT(*) FROM videos v WHERE v.user_id = u.id) AS video_count
            FROM users u
            WHERE u.username LIKE ?
            ORDER BY CASE WHEN u.username = ? THEN 0 ELSE 1 END, u.username COLLATE NOCASE
            LIMIT 30
        ''', (f'%{q}%', q)).fetchall()
    else:
        videos = []
        channels = []
    conn.close()
    return render_template('search.html', q=q, videos=videos, channels=channels)


@app.route('/admin')
def admin():
    require_admin()
    conn = get_db()
    reports = conn.execute('''
        SELECT r.*, ru.username AS reporter,
               v.title AS video_title,
               c.body AS comment_body
        FROM reports r
        LEFT JOIN users ru ON ru.id = r.reporter_id
        LEFT JOIN videos v ON v.id = r.video_id
        LEFT JOIN comments c ON c.id = r.comment_id
        WHERE r.status = 'open'
        ORDER BY r.id DESC LIMIT 100
    ''').fetchall()
    users = conn.execute('SELECT id, username, is_admin, created_at FROM users ORDER BY id DESC LIMIT 100').fetchall()
    videos = conn.execute('''
        SELECT v.id, v.title, v.views, v.created_at, u.username,
               (SELECT COUNT(*) FROM likes l WHERE l.video_id = v.id) AS likes
        FROM videos v JOIN users u ON u.id = v.user_id
        ORDER BY v.id DESC LIMIT 100
    ''').fetchall()
    counts = {
        'users': conn.execute('SELECT COUNT(*) FROM users').fetchone()[0],
        'videos': conn.execute('SELECT COUNT(*) FROM videos').fetchone()[0],
        'reports': conn.execute("SELECT COUNT(*) FROM reports WHERE status = 'open'").fetchone()[0],
        'views': conn.execute('SELECT COALESCE(SUM(views),0) FROM videos').fetchone()[0],
    }
    conn.close()
    return render_template('admin.html', reports=reports, users=users, videos=videos, counts=counts)


@app.route('/admin/report/<int:report_id>/close', methods=['POST'])
def close_report(report_id):
    require_admin(); validate_csrf()
    conn = get_db()
    conn.execute("UPDATE reports SET status = 'closed' WHERE id = ?", (report_id,))
    conn.commit(); conn.close()
    flash('신고를 처리 완료로 표시했습니다.')
    return redirect(url_for('admin'))


@app.route('/admin/video/<int:video_id>/delete', methods=['POST'])
def admin_delete_video(video_id):
    require_admin(); validate_csrf()
    conn = get_db()
    video = conn.execute('SELECT * FROM videos WHERE id = ?', (video_id,)).fetchone()
    if not video:
        conn.close(); abort(404)
    conn.execute('DELETE FROM videos WHERE id = ?', (video_id,))
    conn.commit(); conn.close()
    for filename, folder in [(video['filename'], UPLOAD_DIR), (video['thumbnail_filename'], THUMB_DIR)]:
        if filename:
            try: os.remove(os.path.join(folder, filename))
            except FileNotFoundError: pass
    flash('관리자 권한으로 영상을 삭제했습니다.')
    return redirect(url_for('admin'))


@app.route('/healthz')
def healthz():
    return {'status': 'ok'}


@app.route('/media/videos/<path:filename>')
def video_media(filename):
    return send_from_directory(UPLOAD_DIR, filename, conditional=True)


@app.errorhandler(400)
def bad_request(error):
    return render_template('error.html', message=getattr(error, 'description', '잘못된 요청입니다.')), 400


@app.errorhandler(403)
def forbidden(_):
    return render_template('error.html', message='접근 권한이 없습니다.'), 403


@app.errorhandler(413)
def too_large(_):
    return render_template('error.html', message=f'파일이 너무 큽니다. 최대 {MAX_UPLOAD_MB}MB까지 업로드할 수 있습니다.'), 413


@app.errorhandler(404)
def not_found(_):
    return render_template('error.html', message='페이지를 찾을 수 없습니다.'), 404


init_db()

if __name__ == '__main__':
    port = int(os.environ.get('PORT', '5000'))
    debug = os.environ.get('VIDSHARE_DEBUG', 'false').lower() == 'true'
    app.run(host='0.0.0.0', port=port, debug=debug)
