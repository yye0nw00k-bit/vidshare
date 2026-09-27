FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=10000 \
    VIDSHARE_DATA_DIR=/var/data

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app/

RUN test -f /app/app.py \
    && test -f /app/asset_bundle.py \
    && python -c "from asset_bundle import ensure_assets; ensure_assets('/app')" \
    && test -f /app/templates/index.html \
    && python -m compileall -q /app/app.py /app/asset_bundle.py \
    && mkdir -p /app/static/uploads /app/static/thumbnails /var/data

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 10000
CMD ["sh", "-c", "gunicorn --bind 0.0.0.0:${PORT:-10000} --workers 1 --timeout 120 app:app"]
