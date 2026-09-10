# Dev Cookbook

> 自動化與資料處理的可執行食譜。

📖 **網站:<https://loin123-rgb.github.io/dev-cookbook/>**

不是教學文,是備忘錄。收錄實際做過、當下查很久、下次還會再遇到的東西。每篇都是同一個格式:**遇到什麼問題 → 怎麼解 → 完整可跑的程式碼 → 踩過的坑**。

## 食譜

### Excel 與試算表
| 食譜 | 程式碼 |
|:--|:--|
| [依範本批次產生檢驗表](https://loin123-rgb.github.io/dev-cookbook/recipes/excel/batch-fill-template/) | [`examples/python/excel_batch_fill`](examples/python/excel_batch_fill) |
| [把幾百個 .xls 彙整成 Parquet](https://loin123-rgb.github.io/dev-cookbook/recipes/excel/xls-to-parquet/) | [`examples/python/xls_to_parquet`](examples/python/xls_to_parquet) |
| [清理有合併儲存格的髒表](https://loin123-rgb.github.io/dev-cookbook/recipes/excel/clean-messy-sheet/) | [`examples/python/clean_sheet`](examples/python/clean_sheet) |

### Modbus 與儀器
| 食譜 | 程式碼 |
|:--|:--|
| [輪詢暫存器並寫成 CSV](https://loin123-rgb.github.io/dev-cookbook/recipes/modbus/read-registers-to-csv/) | [`examples/python/modbus_logger`](examples/python/modbus_logger) |
| [解碼 32-bit 浮點數與縮放值](https://loin123-rgb.github.io/dev-cookbook/recipes/modbus/decode-registers/) | [`examples/python/modbus_logger/decode.py`](examples/python/modbus_logger/decode.py) |

### 報表產出
| 食譜 | 程式碼 |
|:--|:--|
| [用 Node.js 批次產生 PowerPoint 報告](https://loin123-rgb.github.io/dev-cookbook/recipes/report/pptx-report/) | [`examples/node/pptx-report`](examples/node/pptx-report) |

### 排程與維運
| 食譜 | 程式碼 |
|:--|:--|
| [讓腳本每天自己跑(Windows)](https://loin123-rgb.github.io/dev-cookbook/recipes/ops/windows-scheduler/) | [`examples/ops`](examples/ops) |

## 快速開始

```bash
git clone https://github.com/loin123-rgb/dev-cookbook.git
cd dev-cookbook/examples/python/xls_to_parquet
pip install -r requirements.txt
python consolidate.py --src "D:\封存區" --out archive.parquet
```

## 慣例

- 程式碼**可以直接跑**,不用先補三行才動得了。路徑一律走參數,不寫死。
- 每篇最後都有「踩過的坑」,那才是這本食譜真正的價值。
- Python 3.11+,Node 20+。

## 本機預覽網站

網站用 Jekyll + [just-the-docs](https://github.com/just-the-docs/just-the-docs) 主題,推上 `main` 由 GitHub Pages 自動建置。要在本機預覽:

```bash
gem install bundler jekyll github-pages
bundle exec jekyll serve
```

## 新增一篇食譜

見 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 授權

MIT — 範例程式可自由取用。
