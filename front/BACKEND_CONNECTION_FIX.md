# Vercel에서 EC2 백엔드 연결 실패 해결 방법

## 문제 상황
- Vercel 프론트엔드에서 EC2 백엔드로 연결 실패 (503 에러)
- EC2는 정상 실행 중, Swagger UI 접속 가능
- 에러: "Failed to connect to backend at http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000"

## 가능한 원인 및 해결 방법

### 1. 보안 그룹 설정 확인 (가장 가능성 높음)

**문제**: EC2 보안 그룹에서 Vercel의 서버리스 함수 IP를 허용하지 않음

**해결 방법**:
1. AWS 콘솔 → EC2 → Security Groups
2. 인스턴스의 보안 그룹 선택
3. **Inbound Rules** 확인:
   - Type: Custom TCP
   - Port: 8000
   - Source: `0.0.0.0/0` (모든 IP 허용) 또는 Vercel IP 범위
   - **저장**

**확인 방법**:
```bash
# EC2에 SSH 접속 후
sudo netstat -tlnp | grep 8000
# 또는
sudo systemctl status langchain-backend
```

### 2. 환경 변수 확인

**Vercel 대시보드에서 확인**:
1. Settings → Environment Variables
2. `BACKEND_BASE_URL` 확인:
   - 값: `http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000`
   - 또는 IP 주소: `http://3.39.187.108:8000`
   - **주의**: `https://`가 아닌 `http://` 사용

**테스트**:
- IP 주소로 직접 접속: `http://3.39.187.108:8000/docs`
- 도메인으로 접속: `http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000/docs`

### 3. 백엔드 서비스 상태 확인

**EC2에 SSH 접속 후**:
```bash
# 서비스 상태 확인
sudo systemctl status langchain-backend

# 서비스가 실행 중이 아니면
sudo systemctl start langchain-backend

# 로그 확인
sudo journalctl -u langchain-backend -n 50
```

### 4. 네트워크 연결 테스트

**Vercel Functions 로그에서 확인**:
1. Vercel 대시보드 → Deployments → 최신 배포
2. Functions 탭 → `/api/chat` 함수
3. 에러 로그 확인:
   - 타임아웃 에러인지
   - 연결 거부 에러인지
   - DNS 해석 실패인지

### 5. CORS 설정 확인 (이미 올바르게 설정됨)

백엔드 CORS는 이미 `allow_origins=["*"]`로 설정되어 있으므로 문제 없음.

## 빠른 해결 방법

### 방법 1: 보안 그룹 수정 (권장)

1. **AWS 콘솔** → EC2 → Security Groups
2. 인스턴스의 보안 그룹 선택
3. **Inbound Rules** → **Edit inbound rules**
4. 규칙 추가:
   - Type: Custom TCP
   - Port: 8000
   - Source: `0.0.0.0/0`
   - Description: "Allow Vercel access"
5. **Save rules**

### 방법 2: 환경 변수 IP 주소 사용

Vercel 환경 변수에서:
```
BACKEND_BASE_URL = http://3.39.187.108:8000
```
(도메인 대신 IP 주소 사용)

### 방법 3: 백엔드 서비스 재시작

EC2에 SSH 접속:
```bash
sudo systemctl restart langchain-backend
sudo systemctl status langchain-backend
```

## 확인 체크리스트

- [ ] EC2 보안 그룹에서 포트 8000이 `0.0.0.0/0`으로 열려있음
- [ ] 백엔드 서비스가 실행 중 (`systemctl status langchain-backend`)
- [ ] Vercel 환경 변수 `BACKEND_BASE_URL`이 올바르게 설정됨
- [ ] 브라우저에서 직접 접속 가능 (`http://3.39.187.108:8000/docs`)
- [ ] CORS 설정이 올바름 (`allow_origins=["*"]`)

## 테스트 방법

### 1. 브라우저에서 직접 테스트
```
http://3.39.187.108:8000/docs
```
접속 가능하면 백엔드는 정상 작동 중

### 2. Vercel Functions 로그 확인
Vercel 대시보드 → Functions → 에러 로그 확인

### 3. curl로 테스트
```bash
curl -X POST http://3.39.187.108:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "테스트", "conversation_history": []}'
```

## 가장 가능성 높은 원인

**EC2 보안 그룹 설정**이 가장 가능성 높은 원인입니다.

현재 보안 그룹에서:
- 포트 8000이 특정 IP만 허용하고 있을 수 있음
- Vercel의 서버리스 함수는 동적 IP를 사용하므로 모든 IP를 허용해야 함

**해결**: 보안 그룹에서 포트 8000을 `0.0.0.0/0`으로 열기

