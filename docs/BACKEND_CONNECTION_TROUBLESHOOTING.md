# 백엔드 연결 문제 해결 가이드

## 문제 증상
- HTTP 503 에러: "Failed to connect to backend at http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000"
- Vercel 프론트엔드에서 EC2 백엔드로 연결 실패

## 단계별 진단 및 해결 방법

### 1단계: EC2 보안 그룹 확인 (가장 중요!)

**문제**: EC2 보안 그룹에서 포트 8000이 외부 접근을 허용하지 않음

**해결 방법**:
1. AWS 콘솔 → EC2 → Security Groups
2. 인스턴스에 연결된 보안 그룹 선택
3. **Inbound Rules** 탭 클릭
4. **Edit inbound rules** 클릭
5. 다음 규칙 추가/확인:
   - **Type**: Custom TCP
   - **Port**: 8000
   - **Source**: `0.0.0.0/0` (모든 IP 허용)
   - **Description**: "Allow Vercel access to FastAPI backend"
6. **Save rules** 클릭

**확인 방법**:
```bash
# 브라우저에서 직접 접속 테스트
http://3.39.187.108:8000/docs
# 또는
http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000/docs
```

접속이 안 되면 보안 그룹 문제입니다.

---

### 2단계: 백엔드 서비스 상태 확인

**EC2에 SSH 접속 후 실행**:

```bash
# 1. 서비스 상태 확인
sudo systemctl status langchain-backend

# 2. 서비스가 실행 중이 아니면 시작
sudo systemctl start langchain-backend

# 3. 서비스가 실행 중이면 재시작 (문제 해결을 위해)
sudo systemctl restart langchain-backend

# 4. 서비스 로그 확인 (에러 확인)
sudo journalctl -u langchain-backend -n 100 --no-pager

# 5. 실시간 로그 모니터링
sudo journalctl -u langchain-backend -f
```

**정상 상태 확인**:
- `Active: active (running)` 표시되어야 함
- 로그에 `API server is ready!` 메시지가 있어야 함

---

### 3단계: 포트 바인딩 확인

**EC2에서 실행**:

```bash
# 포트 8000이 0.0.0.0에 바인딩되어 있는지 확인
sudo netstat -tlnp | grep 8000
# 또는
sudo ss -tlnp | grep 8000
```

**예상 출력** (정상):
```
tcp  0  0  0.0.0.0:8000  0.0.0.0:*  LISTEN  12345/python
```

**문제가 있는 경우** (`127.0.0.1:8000`으로 표시):
- `app/main.py`의 224번째 줄이 `host="0.0.0.0"`인지 확인
- systemd 서비스 파일 확인 (아래 참조)

---

### 4단계: systemd 서비스 설정 확인

**EC2에서 실행**:

```bash
# 서비스 파일 확인
cat /etc/systemd/system/langchain-backend.service
```

**확인 사항**:
- `ExecStart`가 올바른 경로를 가리키는지
- `WorkingDirectory`가 올바른지
- `EnvironmentFile`이 `.env` 파일을 가리키는지

**올바른 설정 예시**:
```ini
[Unit]
Description=LangChain FastAPI Backend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/langchain/app
EnvironmentFile=/opt/langchain/.env
ExecStart=/opt/langchain/venv/bin/python main.py
Restart=always

[Install]
WantedBy=multi-user.target
```

**수정 후**:
```bash
sudo systemctl daemon-reload
sudo systemctl restart langchain-backend
```

---

### 5단계: Vercel 환경 변수 확인

**Vercel 대시보드에서 확인**:
1. 프로젝트 → Settings → Environment Variables
2. `BACKEND_BASE_URL` 확인:
   - **값**: `http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000`
   - 또는 IP 주소: `http://3.39.187.108:8000`
   - **주의**: `https://`가 아닌 `http://` 사용
3. **모든 환경**에 설정되어 있는지 확인:
   - Production
   - Preview
   - Development

**환경 변수 수정 후**:
- 새 배포가 필요할 수 있음
- 또는 기존 배포를 재배포

---

### 6단계: 네트워크 연결 테스트

**EC2에서 실행** (로컬 연결 테스트):

```bash
# 1. localhost에서 테스트
curl http://localhost:8000/health

# 2. 외부 IP로 테스트 (EC2 퍼블릭 IP 사용)
curl http://3.39.187.108:8000/health

# 3. Swagger UI 접속 테스트
curl http://localhost:8000/docs
```

**Vercel Functions 로그 확인**:
1. Vercel 대시보드 → Deployments → 최신 배포
2. Functions 탭 → `/api/chat` 또는 `/api/rag` 함수
3. 에러 로그 확인:
   - `[CHAT] Backend URL:` 로그 확인
   - `[CHAT] Failed to connect to backend:` 에러 확인
   - 타임아웃인지, 연결 거부인지, DNS 해석 실패인지 확인

---

### 7단계: 방화벽 확인 (UFW)

**EC2에서 실행**:

```bash
# UFW 상태 확인
sudo ufw status

# 포트 8000이 허용되어 있는지 확인
# 허용되어 있지 않으면:
sudo ufw allow 8000/tcp
sudo ufw reload
```

---

## 빠른 해결 체크리스트

다음 순서로 확인하세요:

- [ ] **EC2 보안 그룹**: 포트 8000이 `0.0.0.0/0`으로 열려있음
- [ ] **백엔드 서비스**: `sudo systemctl status langchain-backend` → `active (running)`
- [ ] **포트 바인딩**: `sudo netstat -tlnp | grep 8000` → `0.0.0.0:8000` 표시
- [ ] **브라우저 접속**: `http://3.39.187.108:8000/docs` 접속 가능
- [ ] **Vercel 환경 변수**: `BACKEND_BASE_URL`이 올바르게 설정됨
- [ ] **방화벽**: UFW가 포트 8000을 허용함

---

## 가장 흔한 원인 및 해결

### 원인 1: 보안 그룹 설정 (90% 확률)
**증상**: 브라우저에서도 접속 불가
**해결**: EC2 보안 그룹에서 포트 8000을 `0.0.0.0/0`으로 열기

### 원인 2: 백엔드 서비스 미실행 (5% 확률)
**증상**: EC2에서 `curl http://localhost:8000/health` 실패
**해결**: `sudo systemctl start langchain-backend`

### 원인 3: 잘못된 바인딩 (3% 확률)
**증상**: `netstat`에서 `127.0.0.1:8000`으로 표시
**해결**: `app/main.py`의 `uvicorn.run(app, host="0.0.0.0", port=port)` 확인

### 원인 4: Vercel 환경 변수 미설정 (2% 확률)
**증상**: Vercel 로그에서 `BACKEND_BASE_URL: NOT SET`
**해결**: Vercel 대시보드에서 환경 변수 설정

---

## 추가 디버깅 명령어

```bash
# EC2에서 전체 상태 확인 스크립트
echo "=== Backend Service Status ==="
sudo systemctl status langchain-backend --no-pager -l

echo -e "\n=== Port Binding ==="
sudo netstat -tlnp | grep 8000

echo -e "\n=== Recent Logs ==="
sudo journalctl -u langchain-backend -n 50 --no-pager

echo -e "\n=== Health Check ==="
curl -s http://localhost:8000/health | jq . || curl -s http://localhost:8000/health

echo -e "\n=== Environment Variables ==="
sudo systemctl show langchain-backend --property=Environment
```

---

## 문제가 계속되면

1. **EC2 인스턴스 재시작**:
   ```bash
   sudo reboot
   # 재부팅 후 자동으로 서비스 시작됨
   ```

2. **서비스 재설정**:
   ```bash
   sudo systemctl stop langchain-backend
   sudo systemctl daemon-reload
   sudo systemctl start langchain-backend
   ```

3. **로그에서 구체적인 에러 확인**:
   ```bash
   sudo journalctl -u langchain-backend -n 200 | grep -i error
   ```

4. **백엔드 수동 실행 테스트**:
   ```bash
   cd /opt/langchain/app
   source ../venv/bin/activate
   python main.py
   # 에러 메시지 확인
   ```

