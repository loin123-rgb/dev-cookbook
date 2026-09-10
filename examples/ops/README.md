# 排程與維運

食譜說明:<https://loin123-rgb.github.io/dev-cookbook/recipes/ops/windows-scheduler/>

| 檔案 | 用途 |
|:--|:--|
| `run_task.cmd` | 排程任務包裝器:切工作目錄、UTF-8、log、失敗才通知、清舊 log |
| `notify_on_fail.ps1` | 失敗時寫入事件檢視器,可選 webhook |
| `register_task.ps1` | 用指令註冊工作排程器任務,可放進版控 |

## 使用步驟

1. 把 `run_task.cmd` 複製到你的腳本旁邊,改掉裡面那行實際要執行的指令。
2. **先手動雙擊 `run_task.cmd` 確認能跑成功**,再談排程。省掉這步會浪費很多時間在猜。
3. 註冊事件來源(需系統管理員,只要做一次):

   ```powershell
   New-EventLog -LogName Application -Source "ScheduledJobs"
   ```

4. 註冊排程:

   ```powershell
   powershell -ExecutionPolicy Bypass -File register_task.ps1 -TaskName "彙整封存區" -ScriptPath "D:\tools\consolidate\run_task.cmd" -At 02:30
   ```

5. 手動觸發驗證:

   ```powershell
   Start-ScheduledTask -TaskName "彙整封存區"
   Get-ScheduledTask -TaskName "彙整封存區" | Get-ScheduledTaskInfo
   ```

   `LastTaskResult` 是 `0` 代表成功。
