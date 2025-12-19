#!/bin/bash

# 로컬에서 EC2로 직접 배포하는 스크립트 (GitHub Actions 없이 사용 가능)

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 환경 변수 확인
if [ -z "$EC2_HOST" ] || [ -z "$EC2_USER" ] || [ -z "$SSH_KEY_PATH" ]; then
  echo -e "${RED}❌ ERROR: Required environment variables not set${NC}"
  echo "Usage: EC2_HOST=54.123.45.67 EC2_USER=ubuntu SSH_KEY_PATH=~/.ssh/langchain_deploy.pem ./scripts/deploy_to_ec2.sh"
  exit 1
fi

DEPLOY_PATH="${DEPLOY_PATH:-/opt/langchain}"

echo -e "${GREEN}🚀 Starting deployment to EC2...${NC}"
echo "Host: $EC2_HOST"
echo "User: $EC2_USER"
echo "Deploy Path: $DEPLOY_PATH"

# SSH 연결 테스트
echo -e "${YELLOW}🔍 Testing SSH connection...${NC}"
if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$EC2_USER@$EC2_HOST" "echo 'SSH OK'"; then
  echo -e "${RED}❌ SSH connection failed${NC}"
  exit 1
fi

# 배포 실행
echo -e "${YELLOW}📦 Deploying to EC2...${NC}"
ssh -i "$SSH_KEY_PATH" "$EC2_USER@$EC2_HOST" << ENDSSH
  set -e

  echo "📂 Navigating to deploy directory..."
  echo "Ensuring deploy directory exists: $DEPLOY_PATH"
  CURRENT_USER=\$(whoami)
  sudo mkdir -p $DEPLOY_PATH
  sudo chown \$CURRENT_USER:\$CURRENT_USER $DEPLOY_PATH
  cd $DEPLOY_PATH || {
    echo "❌ ERROR: Failed to change to directory: $DEPLOY_PATH"
    exit 1
  }

  if [ -d ".git" ]; then
    echo "🔄 Pulling latest changes from main..."
    git fetch origin main
    git reset --hard origin/main
  else
    echo "📥 First deployment: cloning repository..."
    git clone https://github.com/VictoriaPark12/RAG.git .
  fi

  # 백업 생성
  BACKUP_TAG="backup-\$(date +%Y%m%d-%H%M%S)"
  echo "💾 Creating backup: \$BACKUP_TAG"
  git tag \$BACKUP_TAG 2>/dev/null || true

  # 최신 코드 pull
  echo "🔄 Pulling latest changes..."
  git fetch origin main
  git reset --hard origin/main

  # .env 확인 및 생성
  if [ ! -f .env ]; then
    echo "⚠️  WARNING: .env file not found! Creating template..."
    cat > .env << 'ENVEOF'
# PostgreSQL
POSTGRES_USER=langchain
POSTGRES_PASSWORD=changeme_secure_password_here
POSTGRES_DB=langchain
DATABASE_URL=postgresql://langchain:changeme_secure_password_here@localhost:5432/langchain

# QLoRA 설정 (CPU 모드)
USE_QLORA=1
QLORA_BASE_MODEL_PATH=/opt/langchain/app/model/midm
LLM_PROVIDER=huggingface
PYTHONUNBUFFERED=1

# CPU 전용 (CUDA 비활성화)
CUDA_VISIBLE_DEVICES=
ENVEOF
    echo "⚠️  Please edit .env file and update the password and other settings!"
    echo "⚠️  Continuing with default values for now..."
  else
    echo "✅ .env file found"
  fi

  # Python 버전 확인 및 가상환경 생성
  echo "🐍 Checking Python version..."
  PYTHON_CMD=""

  if command -v python3.12 &> /dev/null; then
    PYTHON_CMD=python3.12
  elif command -v python3.11 &> /dev/null; then
    PYTHON_CMD=python3.11
  elif command -v python3.10 &> /dev/null; then
    PYTHON_CMD=python3.10
  elif command -v python3 &> /dev/null; then
    PYTHON_CMD=python3
  fi

  if [ -z "$PYTHON_CMD" ]; then
    echo "❌ Python 3 not found. Installing Python 3..."
    sudo apt update
    sudo apt install -y python3 python3-venv python3-pip
    # 설치 후 명시적으로 python3 사용
    PYTHON_CMD=python3
  fi

  # 변수가 비어있으면 기본값 사용
  if [ -z "$PYTHON_CMD" ]; then
    PYTHON_CMD=python3
  fi

  # Python 버전 출력 (안전하게)
  if [ -n "$PYTHON_CMD" ]; then
    echo "✅ Using Python: $PYTHON_CMD"
    $PYTHON_CMD --version 2>&1 || echo "⚠️  Warning: Could not get Python version"
  else
    echo "✅ Using Python: python3 (default)"
    python3 --version 2>&1 || echo "⚠️  Warning: Could not get Python version"
    PYTHON_CMD=python3
  fi

  # Python 가상환경 확인 및 생성
  if [ ! -d venv ]; then
    echo "🐍 Creating Python virtual environment..."
    # PYTHON_CMD가 비어있으면 python3 직접 사용
    if [ -n "$PYTHON_CMD" ]; then
      $PYTHON_CMD -m venv venv
    else
      python3 -m venv venv
    fi
  fi

  # 디스크 공간 정리
  echo "🧹 Cleaning up disk space..."
  sudo apt clean
  sudo rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

  # 디스크 공간 확인
  echo "💾 Checking disk space..."
  df -h / | tail -1

  echo "📦 Installing/updating dependencies..."
  source venv/bin/activate
  pip install --upgrade pip

  # CPU 전용 torch 먼저 설치 (CUDA 없이, 공간 절약)
  echo "📦 Installing CPU-only PyTorch (saves ~1.5GB)..."
  pip install torch --index-url https://download.pytorch.org/whl/cpu || {
    echo "⚠️  Warning: CPU torch installation failed, trying default..."
  }

  # 나머지 의존성 설치
  echo "📦 Installing other dependencies..."
  pip install -r app/requirements.txt

  # systemd 서비스 파일 생성/업데이트
  echo "⚙️ Creating/updating systemd service..."
  CURRENT_USER=\$(whoami)
  sudo tee /etc/systemd/system/langchain-backend.service > /dev/null << SERVICEEOF
[Unit]
Description=LangChain FastAPI Backend
After=network.target
Wants=network.target

[Service]
Type=simple
User=\$CURRENT_USER
Group=\$CURRENT_USER
WorkingDirectory=$DEPLOY_PATH/app
Environment="PATH=$DEPLOY_PATH/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=$DEPLOY_PATH/.env
ExecStart=$DEPLOY_PATH/venv/bin/python main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=langchain-backend

[Install]
WantedBy=multi-user.target
SERVICEEOF

  # systemd 재로드 및 서비스 활성화
  echo "⚙️ Reloading systemd and enabling service..."
  sudo systemctl daemon-reload
  sudo systemctl enable langchain-backend || true

  # systemd 서비스 재시작
  echo "♻️  Restarting langchain-backend service..."
  sudo systemctl restart langchain-backend || sudo systemctl start langchain-backend

  # 헬스체크
  echo "⏳ Waiting for service to start..."
  sleep 10

  # 백엔드 상태 확인
  if sudo systemctl is-active --quiet langchain-backend; then
    echo "✅ Backend service is running"
  else
    echo "❌ Backend service failed to start"
    sudo journalctl -u langchain-backend --no-pager -n 50
    exit 1
  fi

  # API 헬스체크
  echo "🔍 Checking API health..."
  for i in {1..30}; do
    if curl -f http://localhost:8000/docs > /dev/null 2>&1; then
      echo "✅ API is healthy!"
      break
    fi
    if [ \$i -eq 30 ]; then
      echo "❌ API health check failed"
      sudo journalctl -u langchain-backend --no-pager -n 50
      exit 1
    fi
    echo "⏳ Waiting for API... (\$i/30)"
    sleep 2
  done

  # 환경 변수 확인 (민감한 정보는 마스킹)
  echo "🔍 Checking environment variables..."
  if [ -f .env ]; then
    if grep -q "OPENAI_API_KEY" .env; then
      OPENAI_KEY_LENGTH=\$(grep "^OPENAI_API_KEY=" .env | cut -d'=' -f2 | wc -c)
      if [ \$OPENAI_KEY_LENGTH -gt 10 ]; then
        echo "✅ OPENAI_API_KEY is set (length: \$((OPENAI_KEY_LENGTH-1)) characters)"
      else
        echo "⚠️  OPENAI_API_KEY appears to be empty or too short"
      fi
    else
      echo "⚠️  OPENAI_API_KEY not found in .env file"
    fi
  else
    echo "⚠️  .env file not found"
  fi

  echo "🎉 Deployment completed successfully!"
ENDSSH

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Deployment succeeded${NC}"
  echo -e "${GREEN}🌐 Access your API at: http://$EC2_HOST:8000/docs${NC}"
else
  echo -e "${RED}❌ Deployment failed${NC}"
  exit 1
fi

