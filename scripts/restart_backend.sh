#!/bin/bash

# EC2 백엔드 서버 재시작 스크립트
# GitHub Actions에서 사용

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DEPLOY_PATH="${DEPLOY_PATH:-/opt/langchain}"

echo -e "${YELLOW}🔄 백엔드 서버 재시작 중...${NC}"

# 서비스 상태 확인
echo -e "${YELLOW}📊 현재 서비스 상태:${NC}"
sudo systemctl status langchain-backend --no-pager -l | head -n 10 || true

# 서비스 재시작
echo -e "${YELLOW}♻️  서비스 재시작...${NC}"
sudo systemctl restart langchain-backend

# 서비스 시작 대기
echo -e "${YELLOW}⏳ 서비스 시작 대기 중 (10초)...${NC}"
sleep 10

# 서비스 상태 확인
if sudo systemctl is-active --quiet langchain-backend; then
    echo -e "${GREEN}✅ 백엔드 서비스가 성공적으로 재시작되었습니다${NC}"
    echo ""
    echo -e "${YELLOW}📋 서비스 상태:${NC}"
    sudo systemctl status langchain-backend --no-pager -l | head -n 15
    echo ""
    echo -e "${YELLOW}📋 최근 로그 (마지막 20줄):${NC}"
    sudo journalctl -u langchain-backend --no-pager -n 20
else
    echo -e "${RED}❌ 백엔드 서비스 재시작 실패${NC}"
    echo ""
    echo -e "${RED}📋 에러 로그:${NC}"
    sudo journalctl -u langchain-backend --no-pager -n 50
    exit 1
fi

# 포트 확인
echo ""
echo -e "${YELLOW}🔌 포트 8000 확인:${NC}"
PORT_CHECK=$(sudo netstat -tlnp 2>/dev/null | grep :8000 || sudo ss -tlnp 2>/dev/null | grep :8000 || echo "")
if [ -z "$PORT_CHECK" ]; then
    echo -e "${RED}❌ 포트 8000에 바인딩된 프로세스가 없습니다${NC}"
    exit 1
else
    echo -e "${GREEN}✅ 포트 8000이 사용 중입니다:${NC}"
    echo "$PORT_CHECK"
fi

# Health check
echo ""
echo -e "${YELLOW}🏥 Health check:${NC}"
HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health || echo "000")
if [ "$HEALTH_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✅ Health check 성공 (HTTP $HEALTH_RESPONSE)${NC}"
else
    echo -e "${YELLOW}⚠️  Health check 응답: HTTP $HEALTH_RESPONSE${NC}"
fi

echo ""
echo -e "${GREEN}✅ 백엔드 서버 재시작 완료${NC}"

