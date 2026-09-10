---
title: 首頁
layout: home
nav_order: 1
---

# Dev Cookbook
{: .no_toc }

自動化與資料處理的可執行食譜。每一篇都遵守同一個格式:**遇到什麼問題 → 怎麼解 → 完整可跑的程式碼 → 踩過的坑**。
{: .fs-6 .fw-300 }

[開始翻食譜](recipes/){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[原始碼在 GitHub](https://github.com/loin123-rgb/dev-cookbook){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## 這本食譜在寫什麼

不是教學文,是**備忘錄**。都是實際做過、當下查資料查很久、下次還會再遇到的東西:

- 一份範本要複製成幾百份、每份填不同資料
- 幾百個舊 `.xls` 讓 Power BI 每次重整都要跑十幾分鐘
- 從電表/儀器用 Modbus 撈數值,還要處理 32-bit 浮點數的 word order
- 檢驗結果要自動變成投影片交出去
- 寫好的腳本要每天自己跑,而且出事要看得到 log

## 分類

| 分類 | 內容 |
|:--|:--|
| [Excel 與試算表](recipes/excel/) | 範本批次填寫、舊格式轉換、髒資料清理 |
| [Modbus 與儀器](recipes/modbus/) | 暫存器讀取、資料型別解碼、長時間記錄 |
| [報表產出](recipes/report/) | 用程式產生 PowerPoint 報告 |
| [排程與維運](recipes/ops/) | Windows 工作排程器、log、失敗通知 |

## 怎麼用

每篇食譜右上角都有對應的 `examples/` 資料夾連結,裡面是可以直接執行的完整腳本:

```bash
git clone https://github.com/loin123-rgb/dev-cookbook.git
cd dev-cookbook/examples/python/xls_to_parquet
pip install -r requirements.txt
python consolidate.py --src "D:\封存區" --out data.parquet
```

## 慣例

- 程式碼**可以直接跑**,不用先補三行才動得了。路徑一律走參數,不寫死。
- 每篇最後都有「踩過的坑」,那才是這本食譜真正的價值。
- Python 用 3.11+,Node 用 20+。
