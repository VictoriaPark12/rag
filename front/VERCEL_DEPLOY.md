# Vercel 배포 가이드

이 문서는 `front` 폴더를 Vercel에 배포하는 방법을 설명합니다.

## 사전 준비

1. **Vercel 계정**: 이미 계정이 열려있다고 하셨으니 준비 완료입니다.
2. **GitHub 저장소**: 코드가 GitHub에 푸시되어 있어야 합니다.
3. **EC2 백엔드 URL**: 백엔드 서버의 공개 URL을 확인하세요.
   - 예: `http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000`
   - 또는 도메인이 있다면: `https://api.yourdomain.com`

## 배포 방법 1: Vercel 웹 대시보드 사용 (권장)

### 1단계: 프로젝트 가져오기

1. [Vercel 대시보드](https://vercel.com/dashboard)에 로그인
2. **"Add New..."** → **"Project"** 클릭
3. GitHub 저장소 선택 (또는 GitLab/Bitbucket)
4. 저장소를 선택하고 **"Import"** 클릭

### 2단계: 프로젝트 설정

**중요 설정:**
- **Framework Preset**: `Next.js` (자동 감지됨)
- **Root Directory**: `front` ⚠️ **이것이 중요합니다!**
  - "Configure Project" 화면에서 "Root Directory" 옆의 "Edit" 클릭
  - `front` 입력
- **Build Command**: `pnpm build` (또는 `npm run build`)
- **Output Directory**: `.next` (기본값)
- **Install Command**: `pnpm install` (또는 `npm install`)

### 3단계: 환경 변수 설정

**"Environment Variables"** 섹션에서 다음 변수 추가:

```
BACKEND_BASE_URL = http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000
```

⚠️ **주의사항:**
- EC2 인스턴스의 보안 그룹에서 포트 8000이 공개적으로 열려있어야 합니다.
- HTTPS를 사용하려면 도메인과 SSL 인증서가 필요합니다.

### 4단계: 배포

1. **"Deploy"** 버튼 클릭
2. 빌드가 완료될 때까지 대기 (약 2-3분)
3. 배포 완료 후 제공되는 URL로 접속 확인

## 배포 방법 2: Vercel CLI 사용

### 1단계: Vercel CLI 설치

```bash
npm i -g vercel
```

### 2단계: 로그인

```bash
vercel login
```

### 3단계: 프로젝트 디렉토리로 이동

```bash
cd front
```

### 4단계: 배포

```bash
vercel
```

첫 배포 시:
- **Set up and deploy?** → `Y`
- **Which scope?** → 계정 선택
- **Link to existing project?** → `N` (새 프로젝트)
- **What's your project's name?** → 프로젝트 이름 입력
- **In which directory is your code located?** → `./` (현재 디렉토리)
- **Want to override the settings?** → `Y`
  - **Root Directory?** → `./` (또는 비워두기)
  - **Build Command?** → `pnpm build`
  - **Output Directory?** → `.next`

### 5단계: 환경 변수 설정

```bash
vercel env add BACKEND_BASE_URL
```

프롬프트에 백엔드 URL 입력:
```
http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000
```

환경 적용:
```bash
vercel env pull .env.local
```

### 6단계: 프로덕션 배포

```bash
vercel --prod
```

## 환경 변수 확인

배포 후 환경 변수가 제대로 설정되었는지 확인:

1. Vercel 대시보드 → 프로젝트 → **Settings** → **Environment Variables**
2. `BACKEND_BASE_URL`이 모든 환경(Production, Preview, Development)에 설정되어 있는지 확인

## 문제 해결

### 백엔드 연결 실패

**증상**: 프론트엔드에서 백엔드 API 호출 시 503 에러

**해결 방법:**
1. EC2 보안 그룹 확인:
   - 인바운드 규칙에 포트 8000이 열려있는지 확인
   - 소스: `0.0.0.0/0` (또는 Vercel IP 범위)

2. 백엔드 서비스 상태 확인:
   ```bash
   # EC2에 SSH 접속 후
   sudo systemctl status langchain-backend
   curl http://localhost:8000/docs
   ```

3. 환경 변수 확인:
   - Vercel 대시보드에서 `BACKEND_BASE_URL` 값 확인
   - URL 끝에 슬래시(`/`)가 없는지 확인

### CORS 에러

백엔드에서 CORS 설정이 필요할 수 있습니다. `app/main.py`에서 CORS 설정 확인:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 또는 Vercel 도메인만 허용
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

## 자동 배포 설정

GitHub에 푸시할 때마다 자동 배포되도록 설정:

1. Vercel 대시보드 → 프로젝트 → **Settings** → **Git**
2. **Production Branch**: `main` (또는 기본 브랜치)
3. **Auto-deploy**: 활성화

이제 `main` 브랜치에 푸시하면 자동으로 배포됩니다.

## 다음 단계

1. **도메인 연결** (선택사항):
   - Vercel 대시보드 → 프로젝트 → **Settings** → **Domains**
   - 커스텀 도메인 추가

2. **HTTPS 백엔드 연결** (권장):
   - EC2에 Nginx 리버스 프록시 설정
   - Let's Encrypt로 SSL 인증서 발급
   - `BACKEND_BASE_URL`을 HTTPS URL로 변경

3. **성능 최적화**:
   - Next.js 이미지 최적화
   - API 라우트 캐싱
   - CDN 활용

## 참고

- [Vercel 공식 문서](https://vercel.com/docs)
- [Next.js 배포 가이드](https://nextjs.org/docs/deployment)
- [환경 변수 관리](https://vercel.com/docs/concepts/projects/environment-variables)

