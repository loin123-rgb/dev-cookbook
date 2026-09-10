@echo off
REM ===================================================================
REM  排程任務包裝器
REM  放在腳本旁邊,由工作排程器呼叫這支,不要直接叫 python.exe
REM  說明:https://loin123-rgb.github.io/dev-cookbook/recipes/ops/windows-scheduler/
REM ===================================================================
setlocal

REM UTF-8,否則 Python 輸出的中文在 log 裡會變亂碼
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1

REM 排程器的預設工作目錄是 C:\Windows\System32,一定要切回來
cd /d "%~dp0"

set "LOGDIR=%~dp0logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

REM 用 PowerShell 取時間戳,不受地區設定影響(%date% 格式各機器不同)
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%i"
set "LOG=%LOGDIR%\run_%TS%.log"

echo ============================================ >> "%LOG%"
echo [%TS%] 開始 >> "%LOG%"
echo ============================================ >> "%LOG%"

REM 用專案自己的虛擬環境,不要靠 PATH —— 排程執行時的 PATH 跟你登入時不一樣
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=python"

"%PY%" consolidate.py --src "\\fileserver\測試記錄\封存區" --out "\\fileserver\測試記錄\archive.parquet" >> "%LOG%" 2>&1
REM 執行完立刻抓,中間插任何一行指令 ERRORLEVEL 就被覆蓋了
set "RC=%ERRORLEVEL%"

echo. >> "%LOG%"
echo [%TS%] 結束,exit code=%RC% >> "%LOG%"

REM 只在失敗時通知
if not "%RC%"=="0" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0notify_on_fail.ps1" -ExitCode %RC% -LogPath "%LOG%"
)

REM 只保留最近 30 個 log,不然跑兩年會有 730 個檔
powershell -NoProfile -Command ^
  "Get-ChildItem '%LOGDIR%\run_*.log' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30 | Remove-Item -Force -ErrorAction SilentlyContinue"

endlocal & exit /b %RC%
