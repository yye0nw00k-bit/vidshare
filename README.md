# vidshare

인터넷 공개 배포용 Flask 영상 공유 사이트.

## Render 배포

GitHub 저장소 **최상위**에 이 프로젝트의 파일과 폴더를 그대로 넣습니다.

필수 구조:

```text
app.py
Dockerfile
requirements.txt
render.yaml
templates/index.html
templates/base.html
static/uploads/.gitkeep
static/thumbnails/.gitkeep
```

Render에서 이 저장소를 Web Service로 연결하고 Docker runtime으로 배포하세요.

### 중요
`templates/`와 `static/` 폴더가 GitHub 저장소에 실제로 있어야 합니다. ZIP 파일 자체를 저장소에 올리는 것이 아니라 ZIP을 **압축 해제한 내용**을 올려야 합니다.

관리자 계정:
- 닉네임: 최연욱
- 초기 비밀번호: 151013

공개 운영에서는 Render 환경변수 `VIDSHARE_ADMIN_PASSWORD`를 별도의 강한 비밀번호로 변경하세요.


### 배포 구조 관련
`asset_bundle.py`가 포함되어 있어 GitHub 웹 업로드 과정에서 `templates/` 또는 `static/` 폴더가 빠져도 Docker 빌드 시 필요한 기본 파일을 자동으로 복원합니다. 그래도 가능하면 원본 폴더 구조를 그대로 GitHub에 올리는 것을 권장합니다.


### Render 운영 참고
SQLite 동시 초기화 충돌을 막기 위해 Render용 Gunicorn worker는 1개로 설정되어 있습니다. `init_db()`도 다중 worker 부팅을 고려한 트랜잭션으로 보호됩니다.
