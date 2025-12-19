# Vercel CI/CD 설정 가이드 (front 폴더)

GitHub와 Vercel이 이미 연결된 상태에서 `front` 폴더를 루트 디렉토리로 설정하고 CI/CD를 완성하는 과정입니다.

## 현재 상태 확인

이미지에서 확인된 정보:
- ✅ 배포 상태: Ready Latest (성공)
- ✅ 도메인: `rag-rouge-two.vercel.app`
- ✅ 소스: main 브랜치 연결됨
- ❌ 문제: 404 에러 발생 (Root Directory 설정 필요)

## 1단계: Root Directory 설정 (필수)

### Vercel 대시보드에서 설정

1. **Vercel 대시보드 접속**
   - https://vercel.com/dashboard
   - 프로젝트 `rag` 선택

2. **Settings → General**
   - 페이지 하단으로 스크롤
   - **Root Directory** 섹션 찾기

3. **Root Directory 변경**
   - **Edit** 버튼 클릭
   - `front` 입력
   - **Save** 클릭

4. **재배포**
   - **Deployments** 탭으로 이동
   - 최신 배포의 **⋯** (점 3개) 클릭
   - **Redeploy** 선택
   - 또는 GitHub에 새로운 커밋 푸시

## 2단계: 환경 변수 설정

### 백엔드 연결을 위한 환경 변수

1. **Settings → Environment Variables**

2. **새 환경 변수 추가**
   - **Key**: `BACKEND_BASE_URL`
   - **Value**: `http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000`
   - **Environment**:
     - ✅ Production
     - ✅ Preview
     - ✅ Development
   - **Add** 클릭

3. **저장 확인**
   - 환경 변수가 목록에 표시되는지 확인

## 3단계: 빌드 설정 확인

### 자동 감지된 설정 확인

1. **Settings → General**

2. **Build & Development Settings** 확인:
   - **Framework Preset**: `Next.js` (자동 감지)
   - **Build Command**: `pnpm build` (또는 자동)
   - **Output Directory**: `.next` (기본값)
   - **Install Command**: `pnpm install` (또는 자동)

3. **Root Directory**: `front` (1단계에서 설정)

## 4단계: CI/CD 자동 배포 확인

### GitHub 연동 확인

1. **Settings → Git**

2. **Production Branch** 확인:
   - `main` 브랜치로 설정되어 있는지 확인
   - 자동 배포가 활성화되어 있는지 확인

3. **자동 배포 테스트**:
   ```bash
   # 로컬에서 테스트
   cd front
   # 작은 변경사항 추가 (예: 주석 추가)
   git add .
   git commit -m "test: vercel auto deploy"
   git push origin main
   ```
   - 푸시 후 Vercel 대시보드에서 자동 배포 시작 확인

## 5단계: 배포 확인

### 배포 성공 확인

1. **Deployments 탭**
   - 최신 배포 상태가 **Ready**인지 확인
   - 빌드 로그에 에러가 없는지 확인

2. **URL 접속 테스트**
   - `https://rag-rouge-two.vercel.app` 접속
   - 정상적으로 프론트엔드 화면이 보여야 함
   - 404 에러가 사라져야 함

3. **API 연결 테스트**
   - 브라우저 Console (F12)에서:
   ```javascript
   fetch('/api/chat', {
     method: 'POST',
     headers: { 'Content-Type': 'application/json' },
     body: JSON.stringify({
       message: '테스트',
       conversation_history: []
     })
   })
   .then(res => res.json())
   .then(data => console.log('✅ 성공:', data))
   .catch(err => console.error('❌ 실패:', err));
   ```

## 6단계: 문제 해결

### 404 에러가 계속되면

1. **Root Directory 재확인**
   - Settings → General → Root Directory
   - 정확히 `front`로 설정되어 있는지 확인
   - 앞뒤 공백 없이

2. **빌드 로그 확인**
   - Deployments → 최신 배포 → Build Logs
   - 에러 메시지 확인

3. **파일 구조 확인**
   - `front/app/page.tsx` 파일이 존재하는지 확인
   - `front/package.json` 파일이 존재하는지 확인

### 빌드 실패 시

1. **로컬 빌드 테스트**
   ```bash
   cd front
   pnpm install
   pnpm build
   ```
   - 로컬에서 빌드가 성공하는지 확인

2. **의존성 확인**
   - `front/package.json`의 의존성이 올바른지 확인
   - `pnpm-lock.yaml`이 최신인지 확인

## 7단계: 최종 확인 체크리스트

배포 완료 후 확인:

- [ ] Root Directory가 `front`로 설정됨
- [ ] 환경 변수 `BACKEND_BASE_URL`이 설정됨
- [ ] 배포 상태가 **Ready**임
- [ ] Vercel URL 접속 시 404 에러가 없음
- [ ] 프론트엔드 화면이 정상적으로 보임
- [ ] API 호출이 정상적으로 작동함
- [ ] GitHub 푸시 시 자동 배포가 작동함

## 빠른 설정 요약

1. **Vercel 대시보드** → 프로젝트 → **Settings** → **General**
2. **Root Directory**: `front` 설정
3. **Settings** → **Environment Variables**
   - `BACKEND_BASE_URL` = `http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000`
4. **Deployments** → 최신 배포 → **Redeploy**
5. 배포 완료 후 URL 접속 확인

## 참고

- **프로젝트 URL**: `https://rag-rouge-two.vercel.app`
- **GitHub 저장소**: `VictoriaPark12/RAG`
- **브랜치**: `main`
- **Root Directory**: `front`

이제 GitHub에 푸시할 때마다 자동으로 Vercel에 배포됩니다!

