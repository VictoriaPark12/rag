# 환경 변수 설정 가이드

로컬과 Vercel에서 다른 모델을 사용하도록 설정되었습니다.

## 설정 요약

- **로컬 (localhost:3000)**: midm 모델 사용 (백엔드 연결)
- **Vercel 배포**: OpenAI API 사용

## Vercel 환경 변수 설정

### 1. Vercel 대시보드에서 설정

1. **Settings → Environment Variables**로 이동

2. **다음 환경 변수 추가:**

   #### 필수 변수
   ```
   Key: OPENAI_API_KEY
   Value: sk-... (OpenAI API 키)
   Environments: Production, Preview, Development 모두 체크
   ```

   #### 선택 변수
   ```
   Key: OPENAI_MODEL
   Value: gpt-4o-mini (또는 gpt-3.5-turbo, gpt-4 등)
   Environments: Production, Preview, Development 모두 체크
   ```

   #### 백엔드 연결 (필수)
   ```
   Key: BACKEND_BASE_URL
   Value: http://ec2-13-209-75-64.ap-northeast-2.compute.amazonaws.com:8000
   Environments: Production, Preview, Development 모두 체크
   Note: EC2 백엔드 서버 주소 (포트 8000)
   ```

3. **Save** 클릭

4. **재배포**
   - Deployments → 최신 배포 → Redeploy

## 로컬 환경 설정

### 1. `.env.local` 파일 생성

`front` 폴더에 `.env.local` 파일 생성:

```bash
cd front
touch .env.local
```

### 2. 환경 변수 설정

`.env.local` 파일에 다음 내용 추가:

```env
# 로컬에서는 백엔드(midm) 사용
BACKEND_BASE_URL=http://localhost:8000

# OpenAI 사용 안 함 (로컬)
USE_OPENAI=false
```

## 동작 방식

### Chat API (`/api/chat`)

- **로컬**: 백엔드(`http://localhost:8000/chat`)로 요청 → midm 모델 사용
- **Vercel**: OpenAI API 직접 호출 → GPT 모델 사용

### RAG API (`/api/rag`)

- **로컬**: 백엔드(`http://localhost:8000/rag`)로 요청 → midm 모델 + 벡터 스토어
- **Vercel**: 백엔드(`BACKEND_BASE_URL/rag`)로 요청 → 백엔드의 모델 사용

## 확인 방법

### 로컬 테스트

```bash
cd front
pnpm dev
```

브라우저에서 `http://localhost:3000` 접속:
- Chat: midm 모델 사용 (백엔드 연결)
- RAG: midm 모델 + 벡터 스토어 사용

### Vercel 테스트

Vercel URL 접속:
- Chat: OpenAI API 사용
- RAG: 백엔드 연결 (벡터 스토어 필요)

## 문제 해결

### Vercel에서 OpenAI가 작동하지 않으면

1. **환경 변수 확인**
   - `OPENAI_API_KEY`가 설정되어 있는지 확인
   - Vercel 대시보드 → Settings → Environment Variables

2. **재배포**
   - 환경 변수 변경 후 반드시 재배포 필요

3. **로그 확인**
   - Vercel 대시보드 → Deployments → Functions 탭
   - 에러 로그 확인

### 로컬에서 백엔드 연결 실패

1. **백엔드 서버 실행 확인**
   ```bash
   # 백엔드가 실행 중인지 확인
   curl http://localhost:8000/docs
   ```

2. **환경 변수 확인**
   - `.env.local` 파일에 `BACKEND_BASE_URL`이 올바르게 설정되어 있는지 확인

## 참고

- Vercel 환경에서는 자동으로 `VERCEL=1` 환경 변수가 설정됩니다
- 로컬에서는 `USE_OPENAI=false`로 설정하여 백엔드 사용
- RAG는 벡터 스토어가 필요하므로 백엔드를 통해야 합니다

