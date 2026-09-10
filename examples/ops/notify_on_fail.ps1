<#
.SYNOPSIS
    排程任務失敗時發出通知。成功時什麼都不做。

.DESCRIPTION
    只在失敗時通知。成功也發信的話,三天後你就會把它設成規則丟進垃圾桶,
    然後真的失敗時也看不到。

    預設寫進 Windows 事件檢視器(不依賴任何外部服務),
    事件檢視器可以再掛一個「發生此事件時寄信」的排程。

    第一次使用前需以系統管理員身分註冊來源(只要做一次):
        New-EventLog -LogName Application -Source "ScheduledJobs"

.EXAMPLE
    powershell -File notify_on_fail.ps1 -ExitCode 1 -LogPath .\logs\run_20260910_023000.log
#>
param(
    [Parameter(Mandatory)] [int]    $ExitCode,
    [Parameter(Mandatory)] [string] $LogPath,
    [string] $TaskName = "排程任務",
    [int]    $TailLines = 40,
    [string] $WebhookUrl = ""   # 給了就同時打 webhook(Teams / Slack / 內部系統)
)

if ($ExitCode -eq 0) { exit 0 }

$tail = if (Test-Path $LogPath) {
    Get-Content $LogPath -Tail $TailLines -Encoding UTF8 | Out-String
} else {
    "(找不到 log 檔:$LogPath)"
}

$message = @"
$TaskName 失敗
主機:$env:COMPUTERNAME
時間:$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Exit code:$ExitCode
Log:$LogPath

最後 $TailLines 行:
$tail
"@

# --- 通知方式一:Windows 事件檢視器 ---
try {
    Write-EventLog -LogName Application -Source "ScheduledJobs" `
        -EventId 9001 -EntryType Error -Message $message -ErrorAction Stop
    Write-Host "已寫入事件檢視器 (Application / ScheduledJobs / 9001)"
} catch {
    Write-Warning "寫入事件記錄失敗(來源可能還沒註冊):$_"
}

# --- 通知方式二:webhook(選用) ---
if ($WebhookUrl) {
    try {
        $body = @{ text = $message } | ConvertTo-Json -Depth 3
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType "application/json; charset=utf-8" `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -ErrorAction Stop
        Write-Host "已送出 webhook 通知"
    } catch {
        Write-Warning "webhook 通知失敗:$_"
    }
}

exit 0
