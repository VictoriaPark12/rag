# Vercel 환경 변수 설정 가이드

이 문서는 Vercel 대시보드에서 환경 변수를 설정하는 방법을 안내합니다.

## 📋 설정해야 할 환경 변수

### 1. Vercel 대시보드 접속

1. [Vercel 대시보드](https://vercel.com/dashboard)에 로그인
2. 프로젝트 선택 (예: `rag-front` 또는 `devictoria`)
3. **Settings** → **Environment Variables** 클릭

### 2. 필수 환경 변수 설정

#### `BACKEND_BASE_URL` (필수)

백엔드 서버 주소를 설정합니다.

**설정 방법:**
1. **Key** 입력란에: `BACKEND_BASE_URL`
2. **Value** 입력란에: `http://ec2-13-209-75-64.ap-northeast-2.compute.amazonaws.com:8000`
3. **Environments** 체크박스:
   - ✅ Production
   - ✅ Preview
   - ✅ Development
4. **Save** 버튼 클릭

**Note (선택사항):**
```
EC2 백엔드 서버 주소입니다. 
도메인: https://www.devictoria.shop/
EC2 DNS: ec2-13-209-75-64.ap-northeast-2.compute.amazonaws.com
포트: 8000
```

#### `OPENAI_API_KEY` (선택사항)

Chat API에서 OpenAI를 직접 사용하는 경우에만 필요합니다.
현재는 백엔드를 통해 OpenAI를 사용하므로 필수는 아닙니다.

**설정 방법:**
1. **Key** 입력란에: `OPENAI_API_KEY`
2. **Value** 입력란에: `sk-proj-...` (실제 OpenAI API 키)
3. **Environments** 체크박스:
   - ✅ Production
   - ✅ Preview
   - ✅ Development
4. **Save** 버튼 클릭

## 🔄 환경 변수 적용 방법

환경 변수를 추가하거나 수정한 후에는 **반드시 재배포**해야 합니다.

### 방법 1: Vercel 대시보드에서 재배포

1. **Deployments** 탭으로 이동
2. 최신 배포 항목의 **⋯** (점 3개) 메뉴 클릭
3. **Redeploy** 선택
4. 확인 대화상자에서 **Redeploy** 클릭

### 방법 2: Git Push로 재배포

```bash
# 아무 변경사항이나 커밋하고 푸시
git commit --allow-empty -m "Trigger redeploy for env vars"
git push origin main
```

## ✅ 설정 확인

### 1. Vercel 대시보드에서 확인

1. **Settings** → **Environment Variables**
2. 설정한 환경 변수들이 표시되는지 확인
3. 각 환경 변수의 **Environments** 열에서 적용 환경 확인

### 2. 배포 로그에서 확인

1. **Deployments** → 최신 배포 클릭
2. **Functions** 탭에서 로그 확인
3. 다음 로그가 보이면 정상:
   ```
   [CHAT] Backend URL: http://ec2-13-209-75-64.ap-northeast-2.compute.amazonaws.com:8000
   [CHAT] Environment variables: { BACKEND_BASE_URL: 'SET', VERCEL: '1' }
   ```

### 3. 브라우저에서 테스트

1. https://www.devictoria.shop/ 접속
2. 개발자 도구 (F12) → **Console** 탭
3. 네트워크 요청이 성공하는지 확인

## 🚨 문제 해결

### 환경 변수가 적용되지 않을 때

1. **재배포 확인**: 환경 변수 변경 후 반드시 재배포했는지 확인
2. **환경 확인**: Production, Preview, Development 모두 체크했는지 확인
3. **값 확인**: URL 끝에 슬래시(`/`)가 없는지 확인
4. **대소문자 확인**: `BACKEND_BASE_URL` (대문자)로 정확히 입력했는지 확인

### 백엔드 연결 실패 시

1. **EC2 보안 그룹 확인**:
   - 인바운드 규칙에 포트 8000이 열려있는지 확인
   - 소스: `0.0.0.0/0` (모든 IP 허용)

2. **백엔드 서비스 상태 확인**:
   ```bash
   # EC2에 SSH 접속 후
   sudo systemctl status langchain-backend
   curl http://localhost:8000/docs
   ```

3. **환경 변수 값 확인**:
   - Vercel 대시보드에서 `BACKEND_BASE_URL` 값 확인
   - `http://`로 시작하는지 확인
   - 포트 번호 `:8000`이 포함되어 있는지 확인

## 📝 현재 설정 요약

| 환경 변수 | 값 | 필수 여부 |
|---------|-----|----------|
| `BACKEND_BASE_URL` | `http://ec2-13-209-75-64.ap-northeast-2.compute.amazonaws.com:8000` | ✅ 필수 |
| `OPENAI_API_KEY` | `sk-proj-...` | ⚠️ 선택 (백엔드에서 사용) |

## 🔗 관련 링크

- [Vercel 환경 변수 문서](https://vercel.com/docs/concepts/projects/environment-variables)
- 프로젝트 URL: https://www.devictoria.shop/
- EC2 백엔드: http://ec2-13-209-75-64.ap-northeast-2.compute.amazonaws.com:8000/docs


