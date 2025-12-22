#!/bin/bash

# 백엔드 연결 문제 진단 스크립트
# EC2 인스턴스에서 실행하세요

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}백엔드 연결 문제 진단 스크립트${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. 백엔드 서비스 상태 확인
echo -e "${YELLOW}[1/6] 백엔드 서비스 상태 확인${NC}"
if systemctl is-active --quiet langchain-backend; then
    echo -e "${GREEN}✅ 백엔드 서비스가 실행 중입니다${NC}"
    systemctl status langchain-backend --no-pager -l | head -n 10
else
    echo -e "${RED}❌ 백엔드 서비스가 실행 중이 아닙니다${NC}"
    echo -e "${YELLOW}서비스를 시작하려면: sudo systemctl start langchain-backend${NC}"
fi
echo ""

# 2. 포트 바인딩 확인
echo -e "${YELLOW}[2/6] 포트 8000 바인딩 확인${NC}"
PORT_CHECK=$(sudo netstat -tlnp 2>/dev/null | grep :8000 || sudo ss -tlnp 2>/dev/null | grep :8000 || echo "")
if [ -z "$PORT_CHECK" ]; then
    echo -e "${RED}❌ 포트 8000에 바인딩된 프로세스가 없습니다${NC}"
    echo -e "${YELLOW}백엔드 서비스가 실행 중인지 확인하세요${NC}"
else
    echo -e "${GREEN}✅ 포트 8000이 사용 중입니다:${NC}"
    echo "$PORT_CHECK"

    # 0.0.0.0에 바인딩되어 있는지 확인
    if echo "$PORT_CHECK" | grep -q "0.0.0.0:8000"; then
        echo -e "${GREEN}✅ 올바르게 0.0.0.0:8000에 바인딩되어 있습니다${NC}"
    elif echo "$PORT_CHECK" | grep -q "127.0.0.1:8000"; then
        echo -e "${RED}❌ 문제 발견: 127.0.0.1:8000에만 바인딩되어 있습니다${NC}"
        echo -e "${YELLOW}해결: app/main.py에서 host='0.0.0.0'으로 설정되어 있는지 확인하세요${NC}"
    else
        echo -e "${YELLOW}⚠️  바인딩 주소를 확인할 수 없습니다${NC}"
    fi
fi
echo ""

# 3. 로컬 헬스체크
echo -e "${YELLOW}[3/6] 로컬 헬스체크 (localhost:8000)${NC}"
if curl -s -f http://localhost:8000/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ localhost:8000/health 응답 성공${NC}"
    curl -s http://localhost:8000/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8000/health
else
    echo -e "${RED}❌ localhost:8000/health 응답 실패${NC}"
    echo -e "${YELLOW}백엔드 서비스가 제대로 시작되지 않았을 수 있습니다${NC}"
fi
echo ""

# 4. 외부 IP로 헬스체크
echo -e "${YELLOW}[4/6] 외부 IP 헬스체크${NC}"
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
if [ -z "$PUBLIC_IP" ]; then
    echo -e "${YELLOW}⚠️  퍼블릭 IP를 가져올 수 없습니다 (EC2 인스턴스가 아닐 수 있음)${NC}"
else
    echo "퍼블릭 IP: $PUBLIC_IP"
    if curl -s -f --max-time 5 http://$PUBLIC_IP:8000/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ $PUBLIC_IP:8000/health 응답 성공${NC}"
    else
        echo -e "${RED}❌ $PUBLIC_IP:8000/health 응답 실패${NC}"
        echo -e "${YELLOW}가능한 원인:${NC}"
        echo "  1. EC2 보안 그룹에서 포트 8000이 열려있지 않음"
        echo "  2. 방화벽(UFW)이 포트 8000을 차단함"
    fi
fi
echo ""

# 5. 최근 로그 확인
echo -e "${YELLOW}[5/6] 최근 백엔드 서비스 로그 (마지막 20줄)${NC}"
if systemctl list-units | grep -q langchain-backend; then
    echo -e "${BLUE}--- 서비스 로그 시작 ---${NC}"
    sudo journalctl -u langchain-backend -n 20 --no-pager | tail -n 20
    echo -e "${BLUE}--- 서비스 로그 끝 ---${NC}"

    # 에러 로그 확인
    ERROR_COUNT=$(sudo journalctl -u langchain-backend -n 100 --no-pager | grep -i "error\|exception\|failed" | wc -l)
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo -e "${RED}⚠️  최근 로그에서 $ERROR_COUNT개의 에러/예외가 발견되었습니다${NC}"
        echo -e "${YELLOW}상세 로그 확인: sudo journalctl -u langchain-backend -n 100${NC}"
    else
        echo -e "${GREEN}✅ 최근 로그에 에러가 없습니다${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  langchain-backend 서비스를 찾을 수 없습니다${NC}"
fi
echo ""

# 6. 방화벽(UFW) 상태 확인
echo -e "${YELLOW}[6/6] 방화벽(UFW) 상태 확인${NC}"
if command -v ufw > /dev/null 2>&1; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null | head -n 1)
    echo "UFW 상태: $UFW_STATUS"

    if echo "$UFW_STATUS" | grep -q "Status: active"; then
        echo -e "${YELLOW}⚠️  UFW가 활성화되어 있습니다${NC}"
        PORT_8000_RULE=$(sudo ufw status | grep "8000" || echo "")
        if [ -z "$PORT_8000_RULE" ]; then
            echo -e "${RED}❌ 포트 8000이 UFW 규칙에 없습니다${NC}"
            echo -e "${YELLOW}해결: sudo ufw allow 8000/tcp${NC}"
        else
            echo -e "${GREEN}✅ 포트 8000이 UFW 규칙에 있습니다:${NC}"
            echo "$PORT_8000_RULE"
        fi
    else
        echo -e "${GREEN}✅ UFW가 비활성화되어 있습니다 (문제 없음)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  UFW가 설치되어 있지 않습니다 (문제 없음)${NC}"
fi
echo ""

# 요약 및 권장 사항
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}진단 완료${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}다음 단계:${NC}"
echo "1. AWS 콘솔에서 EC2 보안 그룹 확인:"
echo "   - 포트 8000이 0.0.0.0/0으로 열려있는지 확인"
echo ""
echo "2. 서비스 재시작 (문제가 있으면):"
echo "   sudo systemctl restart langchain-backend"
echo "   sudo systemctl status langchain-backend"
echo ""
echo "3. 상세 로그 확인:"
echo "   sudo journalctl -u langchain-backend -f"
echo ""
echo "4. 브라우저에서 직접 접속 테스트:"
if [ -n "$PUBLIC_IP" ]; then
    echo "   http://$PUBLIC_IP:8000/docs"
fi
echo "   http://ec2-3-39-187-108.ap-northeast-2.compute.amazonaws.com:8000/docs"

