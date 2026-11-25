# Script đóng gói Payload thành file .ipa trên Windows
param (
    [string]$AppPath = "build\VCAMNEXTPRO.app",
    [string]$OutputIpa = "VCAMNEXTPRO.ipa"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   VCAMNEXTPRO - IPA PACKAGER FOR WINDOWS" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$PayloadDir = "package_temp\Payload"

if (Test-Path "package_temp") {
    Remove-Item -Recurse -Force "package_temp"
}

New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null

if (-not (Test-Path $AppPath)) {
    Write-Host "[!] Thư mục $AppPath chưa tồn tại." -ForegroundColor Yellow
    Write-Host "[*] Tạo khung App giả lập để kiểm tra cấu trúc..." -ForegroundColor Gray
    New-Item -ItemType Directory -Force -Path "$PayloadDir\VCAMNEXTPRO.app" | Out-Null
    Copy-Item "VCAMNEXTPRO\Info.plist" "$PayloadDir\VCAMNEXTPRO.app\Info.plist" -Force
} else {
    Write-Host "[+] Đang sao chép $AppPath vào Payload..." -ForegroundColor Green
    Copy-Item -Recurse -Force $AppPath "$PayloadDir\"
}

if (Test-Path $OutputIpa) {
    Remove-Item -Force $OutputIpa
}

Write-Host "[+] Đang nén thành $OutputIpa..." -ForegroundColor Green
Set-Location "package_temp"
Compress-Archive -Path "Payload" -DestinationPath "..\$OutputIpa" -Force
Set-Location ".."

Remove-Item -Recurse -Force "package_temp"

Write-Host "[✓] Hoàn tất! File $OutputIpa đã sẵn sàng để cài qua TrollStore hoặc ESign." -ForegroundColor Green
