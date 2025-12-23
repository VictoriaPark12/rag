#!/bin/bash

# EC2 백엔드 서버 상태 확인 및 재시작 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}백엔드 서버 상태 확인${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. 서비스 상태 확인
echo -e "${YELLOW}[1/5] 서비스 상태 확인${NC}"
if sudo systemctl is-active --quiet langchain-backend; then
    echo -e "${GREEN}✅ 백엔드 서비스가 실행 중입니다${NC}"
    sudo systemctl status langchain-backend --no-pager -l | head -n 15
else
    echo -e "${RED}❌ 백엔드 서비스가 실행 중이 아닙니다${NC}"
fi
echo ""

# 2. 포트 확인
echo -e "${YELLOW}[2/5] 포트 8000 확인${NC}"
PORT_CHECK=$(sudo netstat -tlnp 2>/dev/null | grep :8000 || sudo ss -tlnp 2>/dev/null | grep :8000 || echo "")
if [ -z "$PORT_CHECK" ]; then
    echo -e "${RED}❌ 포트 8000에 바인딩된 프로세스가 없습니다${NC}"
else
    echo -e "${GREEN}✅ 포트 8000이 사용 중입니다:${NC}"
    echo "$PORT_CHECK"
fi
echo ""

# 3. 최근 로그 확인
echo -e "${YELLOW}[3/5] 최근 로그 확인 (마지막 30줄)${NC}"
sudo journalctl -u langchain-backend --no-pager -n 30
echo ""

# 4. .env 파일 확인
echo -e "${YELLOW}[4/5] .env 파일 확인${NC}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/langchain}"
if [ -f "$DEPLOY_PATH/.env" ]; then
    echo -e "${GREEN}✅ .env 파일이 존재합니다${NC}"
    echo "주요 설정 확인:"
    grep -E "^(LLM_PROVIDER|USE_QLORA|OPENAI_API_KEY|BACKEND_BASE_URL)=" "$DEPLOY_PATH/.env" | sed 's/=.*/=***/' || echo "  (관련 설정 없음)"
else
    echo -e "${RED}❌ .env 파일이 없습니다: $DEPLOY_PATH/.env${NC}"
fi
echo ""

# 5. 서비스 재시작 옵션
echo -e "${YELLOW}[5/5] 서비스 재시작${NC}"
read -p "서비스를 재시작하시겠습니까? (y/n): " RESTART

if [ "$RESTART" = "y" ] || [ "$RESTART" = "Y" ]; then
    echo "🔄 서비스 재시작 중..."
    sudo systemctl restart langchain-backend
    
    echo "⏳ 서비스 시작 대기 중 (5초)..."
    sleep 5
    
    if sudo systemctl is-active --quiet langchain-backend; then
        echo -e "${GREEN}✅ 서비스가 성공적으로 재시작되었습니다${NC}"
        echo ""
        echo "📋 서비스 상태:"
        sudo systemctl status langchain-backend --no-pager -l | head -n 10
    else
        echo -e "${RED}❌ 서비스 재시작 실패${NC}"
        echo ""
        echo "📋 에러 로그:"
        sudo journalctl -u langchain-backend --no-pager -n 20
    fi
else
    echo "⏭️  서비스 재시작을 건너뜁니다"
    echo ""
    echo "수동으로 재시작하려면:"
    echo "  sudo systemctl restart langchain-backend"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}추가 명령어${NC}"
echo -e "${BLUE}========================================${NC}"
echo "서비스 상태 확인: sudo systemctl status langchain-backend"
echo "서비스 시작: sudo systemctl start langchain-backend"
echo "서비스 중지: sudo systemctl stop langchain-backend"
echo "서비스 재시작: sudo systemctl restart langchain-backend"
echo "로그 실시간 확인: sudo journalctl -u langchain-backend -f"
echo "최근 로그: sudo journalctl -u langchain-backend -n 50"

