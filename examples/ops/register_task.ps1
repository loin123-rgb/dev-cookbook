<#
.SYNOPSIS
    註冊 Windows 工作排程器任務。用指令而不是 GUI,才能放進版控、換機器重跑。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File register_task.ps1 `
        -TaskName "彙整封存區" -ScriptPath "D:\tools\consolidate\run_task.cmd" -At 02:30

.EXAMPLE
    # 移除
    Unregister-ScheduledTask -TaskName "彙整封存區" -Confirm:$false
#>
param(
    [Parameter(Mandatory)] [string] $TaskName,
    [Parameter(Mandatory)] [string] $ScriptPath,
    [string] $At = "02:30",
    [ValidateSet("Daily", "Weekly")] [string] $Frequency = "Daily",
    [string] $DayOfWeek = "Monday",
    [int]    $TimeLimitHours = 2,
    [string] $Description = ""
)

if (-not (Test-Path $ScriptPath)) {
    Write-Error "找不到腳本:$ScriptPath"
    exit 2
}

$action = New-ScheduledTaskAction -Execute $ScriptPath -WorkingDirectory (Split-Path $ScriptPath -Parent)

$trigger = if ($Frequency -eq "Weekly") {
    New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $At
} else {
    New-ScheduledTaskTrigger -Daily -At $At
}

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours $TimeLimitHours) `
    -MultipleInstances IgnoreNew `
    -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 10) `
    -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries

if (-not $Description) {
    $Description = "$Frequency $At 執行 $ScriptPath"
}

Register-ScheduledTask -TaskName $TaskName `
    -Action $action -Trigger $trigger -Settings $settings `
    -Description $Description -RunLevel Limited -Force | Out-Null

Write-Host "已註冊「$TaskName」"
Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo |
    Format-List TaskName, LastRunTime, LastTaskResult, NextRunTime

Write-Host ""
Write-Host "手動觸發一次驗證:  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "查看結果(0=成功):Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo"
