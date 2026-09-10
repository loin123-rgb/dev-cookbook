---
title: 食譜
nav_order: 2
has_children: true
permalink: /recipes/
---

# 食譜

依主題分類。每篇都是獨立的,不用照順序看。

## 索引

### Excel 與試算表
- [依範本批次產生檢驗表](excel/batch-fill-template/) — 一份 `.xlsm` 範本複製成上百份,還要保住下拉選單
- [把幾百個 .xls 彙整成 Parquet](excel/xls-to-parquet/) — 讓 Power BI 從十幾分鐘變幾秒
- [清理有合併儲存格的髒表](excel/clean-messy-sheet/) — 多層表頭、合併格、跳行的表格轉成乾淨 DataFrame

### Modbus 與儀器
- [輪詢暫存器並寫成 CSV](modbus/read-registers-to-csv/) — 一支能跑一整週不掛的記錄器
- [解碼 32-bit 浮點數與縮放值](modbus/decode-registers/) — word order 搞錯就會讀到天文數字

### 報表產出
- [用 Node.js 批次產生 PowerPoint 報告](report/pptx-report/) — 資料進去,投影片出來

### 排程與維運
- [讓腳本每天自己跑(Windows)](ops/windows-scheduler/) — 工作排程器 + log + 失敗才通知
