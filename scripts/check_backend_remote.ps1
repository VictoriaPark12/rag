# Windows PowerShell 스크립트: EC2 백엔드 상태 원격 확인
# 사용법: .\scripts\check_backend_remote.ps1

param(
    [string]$EC2Host = "3.39.187.108",
    [string]$EC2User = "ubuntu",
    [string]$SSHKeyPath = "$env:USERPROFILE\.ssh\langchain-key.pem"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "EC2 백엔드 상태 원격 확인" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# SSH 키 파일 확인
if (-not (Test-Path $SSHKeyPath)) {
    Write-Host "❌ SSH 키 파일을 찾을 수 없습니다: $SSHKeyPath" -ForegroundColor Red
    Write-Host "SSH 키 파일 경로를 확인하거나 -SSHKeyPath 매개변수를 사용하세요." -ForegroundColor Yellow
    exit 1
}

Write-Host "SSH 키: $SSHKeyPath" -ForegroundColor Gray
Write-Host "EC2 호스트: $EC2User@$EC2Host" -ForegroundColor Gray
Write-Host ""

# 1. 서비스 상태 확인
Write-Host "[1/4] 백엔드 서비스 상태 확인..." -ForegroundColor Yellow
$status = ssh -i $SSHKeyPath "$EC2User@$EC2Host" "sudo systemctl status langchain-backend --no-pager" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ 서비스 상태:" -ForegroundColor Green
    $status | Select-String -Pattern "Active:" | ForEach-Object { Write-Host $_.Line -ForegroundColor Green }
} else {
    Write-Host "❌ 서비스 상태 확인 실패" -ForegroundColor Red
    Write-Host $status -ForegroundColor Red
}
Write-Host ""

# 2. 포트 바인딩 확인
Write-Host "[2/4] 포트 8000 바인딩 확인..." -ForegroundColor Yellow
$portCheck = ssh -i $SSHKeyPath "$EC2User@$EC2Host" "sudo netstat -tlnp 2>/dev/null | grep :8000 || sudo ss -tlnp 2>/dev/null | grep :8000 || echo 'NOT_FOUND'" 2>&1
if ($portCheck -match "0\.0\.0\.0:8000") {
    Write-Host "✅ 포트 8000이 0.0.0.0에 바인딩되어 있습니다" -ForegroundColor Green
    Write-Host $portCheck -ForegroundColor Gray
} elseif ($portCheck -match "127\.0\.0\.1:8000") {
    Write-Host "❌ 문제: 포트 8000이 127.0.0.1에만 바인딩되어 있습니다" -ForegroundColor Red
    Write-Host $portCheck -ForegroundColor Red
} elseif ($portCheck -match "NOT_FOUND") {
    Write-Host "❌ 포트 8000에 바인딩된 프로세스가 없습니다" -ForegroundColor Red
} else {
    Write-Host "⚠️  포트 바인딩 정보:" -ForegroundColor Yellow
    Write-Host $portCheck -ForegroundColor Gray
}
Write-Host ""

# 3. 로컬 헬스체크
Write-Host "[3/4] 로컬 헬스체크 (localhost:8000)..." -ForegroundColor Yellow
$healthCheck = ssh -i $SSHKeyPath "$EC2User@$EC2Host" "curl -s -f http://localhost:8000/health 2>&1 || echo 'FAILED'" 2>&1
if ($healthCheck -match "FAILED" -or $LASTEXITCODE -ne 0) {
    Write-Host "❌ localhost:8000/health 응답 실패" -ForegroundColor Red
} else {
    Write-Host "✅ localhost:8000/health 응답 성공" -ForegroundColor Green
    try {
        $healthJson = $healthCheck | ConvertFrom-Json
        Write-Host ($healthJson | ConvertTo-Json -Compress) -ForegroundColor Gray
    } catch {
        Write-Host $healthCheck -ForegroundColor Gray
    }
}
Write-Host ""

# 4. 최근 로그 확인
Write-Host "[4/4] 최근 서비스 로그 (마지막 10줄)..." -ForegroundColor Yellow
$logs = ssh -i $SSHKeyPath "$EC2User@$EC2Host" "sudo journalctl -u langchain-backend -n 10 --no-pager 2>&1" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "최근 로그:" -ForegroundColor Gray
    $logs | Select-Object -Last 10 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }

    # 에러 확인
    $errorCount = ($logs | Select-String -Pattern "error|exception|failed" -CaseSensitive:$false).Count
    if ($errorCount -gt 0) {
        Write-Host "⚠️  최근 로그에서 $errorCount개의 에러/예외가 발견되었습니다" -ForegroundColor Yellow
    } else {
        Write-Host "✅ 최근 로그에 에러가 없습니다" -ForegroundColor Green
    }
} else {
    Write-Host "❌ 로그 확인 실패" -ForegroundColor Red
}
Write-Host ""

# 요약
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "요약" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "다음 단계:" -ForegroundColor Yellow
Write-Host "1. AWS 콘솔에서 EC2 보안 그룹 확인 (포트 8000이 0.0.0.0/0으로 열려있는지)" -ForegroundColor White
Write-Host "2. 브라우저에서 직접 접속 테스트: http://$EC2Host:8000/docs" -ForegroundColor White
Write-Host "3. 서비스 재시작이 필요하면:" -ForegroundColor White
Write-Host "   ssh -i `"$SSHKeyPath`" $EC2User@$EC2Host `"sudo systemctl restart langchain-backend`"" -ForegroundColor Gray
Write-Host ""

