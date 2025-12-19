# Vercel 404 에러 해결 방법

## 문제 원인
Vercel에서 `front` 폴더를 Root Directory로 인식하지 못해서 발생하는 문제입니다.

## 해결 방법

### 방법 1: Vercel 대시보드에서 Root Directory 설정 (권장)

1. **Vercel 대시보드 접속**
   - https://vercel.com/dashboard
   - 프로젝트 선택

2. **Settings → General**
   - **Root Directory** 섹션 찾기
   - **Edit** 클릭
   - `front` 입력
   - **Save** 클릭

3. **재배포**
   - **Deployments** 탭으로 이동
   - 최신 배포의 **⋯** (점 3개) 클릭
   - **Redeploy** 선택

### 방법 2: 프로젝트 삭제 후 재생성

1. **기존 프로젝트 삭제**
   - Vercel 대시보드 → 프로젝트 → Settings → Danger Zone
   - **Delete Project** 클릭

2. **새 프로젝트 생성**
   - **Add New...** → **Project**
   - GitHub 저장소 선택
   - **Import** 클릭

3. **중요 설정**
   - **Root Directory**: `front` 입력 (⚠️ 필수!)
   - **Framework Preset**: Next.js (자동 감지)
   - **Build Command**: `pnpm build` (또는 `npm run build`)
   - **Output Directory**: `.next` (기본값)

4. **환경 변수 설정**
   ```
   BACKEND_BASE_URL = http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000
   ```

5. **Deploy** 클릭

### 방법 3: Vercel CLI로 배포

```bash
# 1. front 디렉토리로 이동
cd front

# 2. Vercel CLI 설치 (없는 경우)
npm i -g vercel

# 3. 로그인
vercel login

# 4. 배포 (첫 배포)
vercel

# 프롬프트에 답변:
# - Set up and deploy? → Y
# - Which scope? → 계정 선택
# - Link to existing project? → N
# - What's your project's name? → 프로젝트 이름
# - In which directory is your code located? → ./
# - Want to override the settings? → Y
#   - Root Directory? → ./
#   - Build Command? → pnpm build
#   - Output Directory? → .next

# 5. 환경 변수 설정
vercel env add BACKEND_BASE_URL production
# 프롬프트에 URL 입력: http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000

# 6. 프로덕션 배포
vercel --prod
```

## 확인 사항

### 1. 빌드 로그 확인
- Vercel 대시보드 → 프로젝트 → **Deployments**
- 최신 배포 클릭 → **Build Logs** 확인
- 에러가 있으면 해결

### 2. 파일 구조 확인
배포 후 다음 경로가 존재해야 합니다:
- `/` → `front/app/page.tsx`가 렌더링됨
- `/api/chat` → `front/app/api/chat/route.ts`가 동작
- `/api/rag` → `front/app/api/rag/route.ts`가 동작

### 3. 환경 변수 확인
- Vercel 대시보드 → 프로젝트 → **Settings** → **Environment Variables**
- `BACKEND_BASE_URL`이 설정되어 있는지 확인

## 빠른 체크리스트

- [ ] Vercel에서 Root Directory가 `front`로 설정되어 있음
- [ ] 빌드가 성공적으로 완료됨 (Build Logs 확인)
- [ ] 환경 변수 `BACKEND_BASE_URL`이 설정됨
- [ ] EC2 백엔드가 실행 중이고 포트 8000이 열려있음

## 여전히 문제가 있다면

1. **빌드 로그 확인**: Vercel 대시보드에서 Build Logs를 확인하고 에러 메시지를 확인하세요.
2. **로컬 빌드 테스트**:
   ```bash
   cd front
   pnpm install
   pnpm build
   ```
   로컬에서 빌드가 성공하는지 확인하세요.

