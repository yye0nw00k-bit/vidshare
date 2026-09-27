# Render 배포

이번 버전은 SQLite를 사용하므로 Render에서는 Gunicorn worker를 1개로 실행합니다. 여러 worker가 동시에 앱을 import할 때 SQLite 초기화가 겹치는 문제를 막았고, `init_db()`에도 `BEGIN IMMEDIATE` + `INSERT OR IGNORE`를 적용했습니다.

## 배포
1. 이 폴더의 **내용물**을 GitHub 저장소 최상위에 올립니다.
2. Render에서 Docker Web Service로 연결합니다.
3. Persistent Disk를 `/var/data`에 연결합니다. `render.yaml`을 사용하면 설정을 가져올 수 있습니다.
4. Render 환경변수에서 `VIDSHARE_ADMIN_PASSWORD`를 원하는 관리자 비밀번호로 설정할 수 있습니다. 기본값은 로컬 실행용 `151013`입니다.

## 정상적인 저장소 구조
```text
app.py
asset_bundle.py
Dockerfile
requirements.txt
render.yaml
templates/
static/
```

## 중요
- ZIP 파일 자체를 GitHub에 넣지 마세요.
- 압축을 푼 뒤 파일과 폴더를 저장소 루트에 올리세요.
- 배포 로그에 `Worker failed to boot`가 나오면 그 앞부분의 첫 Python traceback이 실제 원인입니다.
