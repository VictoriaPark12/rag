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

  # 디스크 공간 정리 (Git pull 전에 먼저 실행)
  echo "🧹 Cleaning up disk space before Git operations..."
  
  # 디스크 사용률 확인
  DISK_USAGE=\$(df / | tail -1 | awk '{print \$5}' | sed 's/%//')
  echo "💾 Current disk usage: \${DISK_USAGE}%"
  
  if [ "\$DISK_USAGE" -gt 80 ]; then
    echo "⚠️  Disk usage is high (\${DISK_USAGE}%). Performing aggressive cleanup..."
    
    # apt 캐시 정리
    echo "🧹 Cleaning apt cache..."
    sudo apt clean 2>/dev/null || true
    sudo apt autoclean 2>/dev/null || true
    
    # 패키지 목록 캐시 정리
    echo "🧹 Cleaning package lists..."
    sudo rm -rf /var/lib/apt/lists/* 2>/dev/null || true
    sudo mkdir -p /var/lib/apt/lists/partial 2>/dev/null || true
    
    # 임시 파일 정리
    echo "🧹 Cleaning temporary files..."
    sudo rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
    
    # 오래된 로그 파일 정리
    echo "🧹 Cleaning old log files..."
    sudo journalctl --vacuum-time=3d 2>/dev/null || true
    sudo find /var/log -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true
    sudo find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
    
    # 오래된 백업 파일 정리 (7일 이상 된 백업)
    if [ -d "$DEPLOY_PATH" ]; then
      echo "🧹 Cleaning old backups..."
      find $DEPLOY_PATH -name "backup-*" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
      # Git 객체 캐시 정리 (안전하게)
      if [ -d "$DEPLOY_PATH/.git/objects" ]; then
        echo "🧹 Cleaning Git object cache..."
        cd $DEPLOY_PATH
        git gc --prune=now --aggressive 2>/dev/null || true
      fi
    fi
    
    # 사용하지 않는 패키지 제거
    echo "🧹 Removing unused packages..."
    sudo apt autoremove -y 2>/dev/null || true
    
    # 디스크 공간 재확인
    DISK_USAGE_AFTER=\$(df / | tail -1 | awk '{print \$5}' | sed 's/%//')
    echo "💾 Disk usage after cleanup: \${DISK_USAGE_AFTER}%"
    
    if [ "\$DISK_USAGE_AFTER" -gt 95 ]; then
      echo "❌ ERROR: Disk space is still critically low (\${DISK_USAGE_AFTER}%)"
      echo "Please manually free up disk space on the EC2 instance"
      df -h /
      echo "💡 Tip: Run 'bash scripts/free_disk_space.sh' or manually clean up files"
      exit 1
    fi
  else
    # 기본 정리만 수행
    sudo apt clean 2>/dev/null || true
    sudo rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
  fi

  # Git 작업 전 디렉토리로 이동
  cd $DEPLOY_PATH || {
    echo "❌ ERROR: Failed to change to directory: $DEPLOY_PATH"
    exit 1
  }

  if [ -d ".git" ]; then
    echo "🔄 Pulling latest changes from main..."
    # 디스크 공간 재확인
    DISK_USAGE=\$(df / | tail -1 | awk '{print \$5}' | sed 's/%//')
    if [ "\$DISK_USAGE" -gt 95 ]; then
      echo "⚠️  WARNING: Disk usage is very high (\${DISK_USAGE}%). Git pull may fail."
      echo "Skipping Git pull and using existing code..."
    else
      git fetch origin main || {
        echo "⚠️  Git fetch failed, trying to continue with existing code..."
        git reset --hard HEAD 2>/dev/null || true
      }
      git reset --hard origin/main || {
        echo "⚠️  Git reset failed, using current HEAD..."
      }
    fi
  else
    echo "📥 First deployment: cloning repository..."
    # 디스크 공간 확인
    DISK_USAGE=\$(df / | tail -1 | awk '{print \$5}' | sed 's/%//')
    if [ "\$DISK_USAGE" -gt 90 ]; then
      echo "❌ ERROR: Cannot clone repository - disk space too low (\${DISK_USAGE}%)"
      df -h /
      exit 1
    fi
    git clone https://github.com/VictoriaPark12/RAG.git .
  fi

  # 백업 생성 (Git pull 성공 후)
  if [ -d ".git" ]; then
    BACKUP_TAG="backup-\$(date +%Y%m%d-%H%M%S)"
    echo "💾 Creating backup tag: \$BACKUP_TAG"
    git tag \$BACKUP_TAG 2>/dev/null || true
  fi

  # openai 폴더 확인 (필수)
  echo "🔍 Verifying openai folder..."
  if [ -d "openai" ]; then
    echo "✅ openai folder exists"
    if [ -f "openai/app/core/llm/openai.py" ]; then
      echo "✅ openai.py file found"
    else
      echo "❌ ERROR: openai.py file not found in openai/app/core/llm/"
      exit 1
    fi
  else
    echo "❌ ERROR: openai folder not found"
    exit 1
  fi

  # .env 확인 및 생성 (OpenAI 모드만 사용, midm 모델 사용 안 함)
  if [ ! -f .env ]; then
    echo "⚠️  WARNING: .env file not found! Creating template..."
    cat > .env << 'ENVEOF'
# PostgreSQL
POSTGRES_USER=langchain
POSTGRES_PASSWORD=changeme_secure_password_here
POSTGRES_DB=langchain
DATABASE_URL=postgresql://langchain:changeme_secure_password_here@localhost:5432/langchain

# OpenAI 설정 (midm 모델 사용 안 함)
LLM_PROVIDER=openai
OPENAI_API_KEY=your_openai_api_key_here
OPENAI_MODEL=gpt-4o-mini
OPENAI_TEMPERATURE=0.7
PYTHONUNBUFFERED=1

# midm 모델 비활성화
USE_QLORA=0
ENVEOF
    echo "⚠️  Please edit .env file and update OPENAI_API_KEY and other settings!"
    echo "⚠️  Continuing with default values for now..."
  else
    echo "✅ .env file found"
    # .env에 LLM_PROVIDER=openai가 없으면 추가
    if ! grep -q "^LLM_PROVIDER=openai" .env; then
      # 기존 LLM_PROVIDER 라인 수정 또는 추가
      if grep -q "^LLM_PROVIDER=" .env; then
        sed -i 's/^LLM_PROVIDER=.*/LLM_PROVIDER=openai/' .env
      else
        echo "LLM_PROVIDER=openai" >> .env
      fi
      echo "✅ Set LLM_PROVIDER=openai in .env"
    fi
    # USE_QLORA 비활성화
    if grep -q "^USE_QLORA=" .env; then
      sed -i 's/^USE_QLORA=.*/USE_QLORA=0/' .env
    else
      echo "USE_QLORA=0" >> .env
    fi
    echo "✅ Disabled QLoRA/midm model in .env"
  fi

  # .env 파일에 OPENAI_API_KEY 확인 및 경고
  echo "🔍 Checking OPENAI_API_KEY in .env file..."
  if [ -f .env ]; then
    # 주석이 아닌 OPENAI_API_KEY 라인 찾기
    OPENAI_KEY_LINE=\$(grep -E "^[^#]*OPENAI_API_KEY=" .env | head -1)
    if [ -n "\$OPENAI_KEY_LINE" ]; then
      OPENAI_KEY_VALUE=\$(echo "\$OPENAI_KEY_LINE" | cut -d'=' -f2- | tr -d ' ')
      if [ -n "\$OPENAI_KEY_VALUE" ] && [ "\$OPENAI_KEY_VALUE" != "your_openai_api_key_here" ]; then
        OPENAI_KEY_LENGTH=\$(echo -n "\$OPENAI_KEY_VALUE" | wc -c)
        if [ \$OPENAI_KEY_LENGTH -gt 10 ]; then
          echo "✅ OPENAI_API_KEY is set in .env file (length: \$OPENAI_KEY_LENGTH characters)"
        else
          echo "⚠️  WARNING: OPENAI_API_KEY in .env appears to be too short (length: \$OPENAI_KEY_LENGTH)"
          echo "⚠️  Please set a valid OPENAI_API_KEY in $DEPLOY_PATH/.env"
        fi
      else
        echo "⚠️  WARNING: OPENAI_API_KEY is set but appears to be empty or placeholder"
        echo "⚠️  Please set a valid OPENAI_API_KEY in $DEPLOY_PATH/.env"
        echo "⚠️  Example: OPENAI_API_KEY=sk-..."
      fi
    else
      echo "⚠️  WARNING: OPENAI_API_KEY not found in .env file"
      echo "⚠️  Please add OPENAI_API_KEY to $DEPLOY_PATH/.env"
      echo "⚠️  Example: OPENAI_API_KEY=sk-..."
    fi
  else
    echo "⚠️  WARNING: .env file not found at $DEPLOY_PATH/.env"
    echo "⚠️  Creating .env file template..."
  fi

  # Python 설치 전 디스크 공간 확인 (이미 정리는 Git pull 전에 수행됨)
  echo "💾 Checking disk space before Python installation..."
  DISK_USAGE=\$(df / | tail -1 | awk '{print \$5}' | sed 's/%//')
  echo "💾 Current disk usage: \${DISK_USAGE}%"
  
  if [ "\$DISK_USAGE" -gt 95 ]; then
    echo "❌ ERROR: Disk space is critically low (\${DISK_USAGE}%)"
    echo "Cannot proceed with Python installation"
    df -h /
    exit 1
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
    # 디스크 공간 재확인
    DISK_USAGE=\$(df / | tail -1 | awk '{print \$5}' | sed 's/%//')
    if [ "\$DISK_USAGE" -gt 95 ]; then
      echo "❌ ERROR: Cannot install Python - disk space too low (\${DISK_USAGE}%)"
      df -h /
      exit 1
    fi
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

  # 디스크 공간 최종 확인
  echo "💾 Final disk space check..."
  df -h / | tail -1
  DISK_USAGE=\$(df / | tail -1 | awk '{print \$5}' | sed 's/%//')
  if [ "\$DISK_USAGE" -gt 95 ]; then
    echo "⚠️  WARNING: Disk usage is very high (\${DISK_USAGE}%). Installation may fail."
  fi

  echo "📦 Installing/updating dependencies..."
  source venv/bin/activate
  pip install --upgrade pip

  # OpenAI 관련 의존성만 설치 (midm 모델 사용 안 함)
  echo "📦 Installing OpenAI dependencies..."
  # openai 패키지를 먼저 강제 재설치 (langchain-openai의 의존성)
  # langchain-openai는 openai>=1.109.1을 요구함
  # --force-reinstall로 기존 버전 제거 후 재설치
  pip uninstall -y openai 2>/dev/null || true
  pip install --force-reinstall --no-cache-dir "openai>=1.109.1,<3.0.0"
  pip install --upgrade langchain-openai>=0.0.5
  pip install python-dotenv>=1.0.0
  pip install fastapi>=0.104.0
  pip install uvicorn[standard]>=0.24.0
  pip install pydantic>=2.0.0
  pip install langchain-core>=0.1.0
  pip install langchain-postgres>=0.0.1
  pip install psycopg2-binary>=2.9.5
  pip install psycopg>=3.1.0
  pip install pgvector>=0.2.4
  pip install sentence-transformers>=2.2.0
  pip install langchain-huggingface>=0.0.1
  pip install numpy>=1.24.0
  echo "✅ OpenAI dependencies installed"

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
# openai 폴더를 Python path에 추가하고 midm/app/main.py 사용 (LLM_PROVIDER=openai로 설정됨)
WorkingDirectory=$DEPLOY_PATH/midm/app
Environment="DEPLOY_PATH=$DEPLOY_PATH"
Environment="PATH=$DEPLOY_PATH/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=$DEPLOY_PATH/.env
# Python path에 openai 폴더 추가 (openai 모듈 import 가능하도록)
# 주의: $DEPLOY_PATH/openai는 app.core.llm.openai를 import하기 위해 필요하지만,
# 실제 openai 패키지와 이름 충돌을 피하기 위해 순서를 조정
# 시스템 패키지가 먼저 로드되도록 하되, app.core.llm.openai는 여전히 import 가능해야 함
Environment="PYTHONPATH=$DEPLOY_PATH:$DEPLOY_PATH/openai:$DEPLOY_PATH/midm/app"
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
  
  # 포트 바인딩 확인
  echo "🔍 Checking if port 8000 is listening..."
  if netstat -tuln 2>/dev/null | grep -q ":8000 " || ss -tuln 2>/dev/null | grep -q ":8000 "; then
    echo "✅ Port 8000 is listening"
  else
    echo "⚠️  Port 8000 is not listening"
  fi
  
  # API 헬스체크 시도
  API_HEALTHY=false
  for i in {1..30}; do
    # 여러 엔드포인트 시도
    if curl -f -s http://localhost:8000/docs > /dev/null 2>&1; then
      echo "✅ API is healthy! (docs endpoint)"
      API_HEALTHY=true
      break
    elif curl -f -s http://localhost:8000/health > /dev/null 2>&1; then
      echo "✅ API is healthy! (health endpoint)"
      API_HEALTHY=true
      break
    elif curl -f -s http://localhost:8000/ > /dev/null 2>&1; then
      echo "✅ API is responding! (root endpoint)"
      API_HEALTHY=true
      break
    fi
    
    if [ \$i -eq 30 ]; then
      echo "❌ API health check failed after 60 seconds"
      echo ""
      echo "📋 Diagnostic information:"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      
      # 서비스 상태
      echo "1. Service status:"
      sudo systemctl status langchain-backend --no-pager -l || true
      echo ""
      
      # 포트 확인
      echo "2. Port 8000 binding:"
      (netstat -tuln 2>/dev/null | grep ":8000 ") || (ss -tuln 2>/dev/null | grep ":8000 ") || echo "  Port 8000 not found"
      echo ""
      
      # 프로세스 확인
      echo "3. Python processes:"
      ps aux | grep -E "python.*main.py|uvicorn" | grep -v grep || echo "  No Python process found"
      echo ""
      
      # 최근 로그
      echo "4. Recent service logs (last 50 lines):"
      sudo journalctl -u langchain-backend --no-pager -n 50
      echo ""
      
      # curl 오류 상세
      echo "5. Curl test results:"
      echo "  Testing /docs:"
      curl -v http://localhost:8000/docs 2>&1 | head -20 || echo "  Failed"
      echo ""
      echo "  Testing /health:"
      curl -v http://localhost:8000/health 2>&1 | head -20 || echo "  Failed"
      echo ""
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "💡 Troubleshooting tips:"
      echo "  1. Check if OPENAI_API_KEY is set in .env file"
      echo "  2. Check service logs: sudo journalctl -u langchain-backend -f"
      echo "  3. Check if port 8000 is open in EC2 security group"
      echo "  4. Try restarting service: sudo systemctl restart langchain-backend"
      
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

