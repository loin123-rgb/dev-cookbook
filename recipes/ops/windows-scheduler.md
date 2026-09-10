---
title: 讓腳本每天自己跑(Windows)
parent: 排程與維運
grand_parent: 食譜
nav_order: 1
permalink: /recipes/ops/windows-scheduler/
---

# 讓腳本每天自己跑(Windows)
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/ops/`](https://github.com/loin123-rgb/dev-cookbook/tree/main/examples/ops)

## 問題

彙整腳本寫好了,但每個月要記得手動跑一次。忘記跑就沒人發現,直到報表出來是舊資料。

## 解法:包一層 .cmd 再交給工作排程器

不要直接在排程器裡填 `python.exe` 加一串參數。包一個 `.cmd`,好處是:路徑固定、可以自己雙擊測試、log 統一。

```bat
@echo off
setlocal
chcp 65001 >nul

REM 切到腳本所在目錄,排程器的預設工作目錄不是這裡
cd /d "%~dp0"

set "LOGDIR=%~dp0logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

REM 用 PowerShell 取得可排序的時間戳,不受地區設定影響
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%i"
set "LOG=%LOGDIR%\run_%TS%.log"

echo [%date% %time%] 開始 >> "%LOG%"

REM 用專案自己的虛擬環境,不要靠 PATH
".venv\Scripts\python.exe" consolidate.py --src "D:\封存區" --out "D:\archive.parquet" >> "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"

echo [%date% %time%] 結束,exit code=%RC% >> "%LOG%"

REM 只保留最近 30 個 log
powershell -NoProfile -Command ^
  "Get-ChildItem '%LOGDIR%\run_*.log' | Sort-Object LastWriteTime -Desc | Select-Object -Skip 30 | Remove-Item -Force"

exit /b %RC%
```

存成 `run_task.cmd`,放在腳本旁邊。

## 註冊排程

用 GUI 也行,但用指令可重現、可以放進版控:

```powershell
$action  = New-ScheduledTaskAction -Execute "D:\tools\consolidate\run_task.cmd"
$trigger = New-ScheduledTaskTrigger -Daily -At 02:30
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -MultipleInstances IgnoreNew `
    -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName "彙整封存區" `
    -Action $action -Trigger $trigger -Settings $settings `
    -Description "每天 02:30 把封存區 Excel 轉成 Parquet" `
    -RunLevel Limited
```

幾個設定的意義:

| 參數 | 為什麼要 |
|:--|:--|
| `-StartWhenAvailable` | 排程時間電腦關著,開機後補跑 |
| `-ExecutionTimeLimit` | 卡住時強制結束,不然會佔著不放 |
| `-MultipleInstances IgnoreNew` | 上一次還沒跑完就不要再啟一個 |
| `-RestartCount 2` | 失敗自動重試兩次 |
| `-RunLevel Limited` | 不需要管理員就不要用,降低風險 |

驗證與手動觸發:

```powershell
Get-ScheduledTask -TaskName "彙整封存區" | Get-ScheduledTaskInfo
Start-ScheduledTask -TaskName "彙整封存區"
```

`Get-ScheduledTaskInfo` 會顯示 `LastTaskResult`,`0` 是成功。

## 失敗才通知

成功也發信,三天後你就會把它設成規則丟進垃圾桶,然後真的失敗時也看不到。**只在失敗時通知**:

```powershell
# notify_on_fail.ps1 — 由 run_task.cmd 在 RC 非 0 時呼叫
param([int]$ExitCode, [string]$LogPath)

if ($ExitCode -eq 0) { exit 0 }

$tail = Get-Content $LogPath -Tail 40 | Out-String
$body = "任務失敗,exit code = $ExitCode`n`n最後 40 行:`n$tail"

# 依環境擇一:企業內部 webhook / SMTP / 寫進事件檢視器
Write-EventLog -LogName Application -Source "ScheduledJobs" `
    -EventId 9001 -EntryType Error -Message $body
```

`Write-EventLog` 需要先註冊來源(只要做一次,需管理員):

```powershell
New-EventLog -LogName Application -Source "ScheduledJobs"
```

好處是不依賴任何外部服務,而且事件檢視器可以再掛一個「發生此事件時寄信」的排程。

## 踩過的坑

**排程器的工作目錄不是腳本所在目錄。**
預設是 `C:\Windows\System32`。所有相對路徑都會失效。`cd /d "%~dp0"` 是每個 `.cmd` 的第一行。

**「不論使用者是否登入」需要儲存密碼,而且會拿不到網路磁碟機。**
勾了這個選項後,`Z:\` 這類對應磁碟機在工作階段裡不存在,腳本會找不到路徑。**一律用 UNC 路徑** `\server\share\...`,不要用磁碟機代號。

**中文 log 變亂碼。**
`.cmd` 預設是 Big5 (cp950),Python 輸出 UTF-8 會亂。`chcp 65001` 之外,Python 端也要固定:

```bat
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
```

**`ERRORLEVEL` 要立刻抓。**
中間插了任何一行指令,`%ERRORLEVEL%` 就被覆蓋了。執行完立刻 `set "RC=%ERRORLEVEL%"`。

**用虛擬環境的絕對路徑,不要靠 `python` 在 PATH 裡。**
排程執行時的 PATH 跟你互動式登入時不一樣,常常整個 conda / pyenv 都不在。寫 `.venv\Scripts\python.exe`。

**log 不清理會塞爆磁碟。**
每天一個 log 跑兩年就是 730 個檔案。範例最後那段 PowerShell 只留 30 個。

**測試時先手動雙擊 `.cmd`。**
能雙擊跑成功,才有資格談排程失敗的原因。省掉這步會浪費很多時間在猜。
