---
title: 把幾百個 .xls 彙整成 Parquet
parent: Excel 與試算表
grand_parent: 食譜
nav_order: 2
permalink: /recipes/excel/xls-to-parquet/
---

# 把幾百個 .xls 彙整成 Parquet
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/python/xls_to_parquet/`](https://github.com/loin123-rgb/dev-cookbook/tree/main/examples/python/xls_to_parquet)

## 問題

Power BI 報表接了一個封存資料夾,裡面有四百多個歷年測試記錄檔。每次按「重新整理」都要跑十幾分鐘,而且會愈來愈慢——因為每個月都在往裡面丟新檔案。

診斷後發現瓶頸不是資料量(全部加起來才幾十萬列),是**檔案數量與格式**:舊的 `.xls`(BIFF8)必須用 `xlrd` 逐檔解析,單檔就要一兩秒,而且**每次重整都會把四百多個檔案全部重讀一次**。

## 解法:把「重讀」變成「增量」

拆成兩層:

```
封存區/*.xls, *.xlsx  ──(每月跑一次的彙整腳本)──>  archive.parquet
                                                        │
本月/*.xlsx ──────────────────────────────────────────> │
                                                        ▼
                                                    Power BI
```

- **封存層**:歷史資料一次轉成單一 Parquet,之後不再碰。
- **滾動層**:只有當月的少數幾個檔案還是 Excel,Power BI 每次重整只讀這幾個。

Power BI 讀 Parquet 幾乎是瞬間的——它是欄式格式、有壓縮、不用解析 XML 或 BIFF。

## 彙整腳本

```python
from pathlib import Path
import pandas as pd

def read_any_excel(path: Path) -> pd.DataFrame:
    """.xls 走 xlrd,.xlsx/.xlsm 走 openpyxl。"""
    engine = "xlrd" if path.suffix.lower() == ".xls" else "openpyxl"
    df = pd.read_excel(path, engine=engine)
    df["來源檔"] = path.name          # 保留出處,日後對帳用得到
    return df

def consolidate(src: Path, out: Path) -> None:
    files = sorted(p for p in src.rglob("*") if p.suffix.lower() in {".xls", ".xlsx", ".xlsm"})
    frames = []
    for i, f in enumerate(files, 1):
        try:
            frames.append(read_any_excel(f))
        except Exception as e:
            print(f"  [略過] {f.name}: {e}")
        print(f"  {i}/{len(files)} {f.name}")

    big = pd.concat(frames, ignore_index=True)
    big.to_parquet(out, engine="pyarrow", compression="zstd", index=False)
    print(f"完成:{len(big):,} 列 → {out} ({out.stat().st_size / 1e6:.1f} MB)")
```

完整版(型別統一、增量快取、平行讀取)在 [`consolidate.py`](https://github.com/loin123-rgb/dev-cookbook/blob/main/examples/python/xls_to_parquet/consolidate.py)。

```bash
pip install pandas pyarrow openpyxl xlrd
python consolidate.py --src "D:\測試記錄\封存區" --out "D:\測試記錄\archive.parquet"
```

## 在 Power BI 端接起來

Power Query 裡新增資料來源選 **Parquet**,或直接寫 M:

```
let
    Source = Parquet.Document(File.Contents("D:\測試記錄\archive.parquet")),
    Current = Excel.Workbook(File.Contents("D:\測試記錄\本月.xlsx"), null, true),
    All = Table.Combine({Source, Current[Data]{0}})
in
    All
```

兩層在最後 `Table.Combine` 疊起來,下游的量測、視覺物件都不用改。

## 效果

實測 432 個檔案(其中 287 個是 `.xls`):

| | 重整時間 | 說明 |
|:--|:--|:--|
| 改造前 | 約 14 分鐘 | 每次重讀 432 個檔 |
| 改造後 | 約 8 秒 | 1 個 Parquet + 3 個當月 Excel |
| 彙整腳本本身 | 約 6 分鐘 | 一個月只跑一次 |

## 踩過的坑

**`xlrd` 2.x 拿掉了 `.xlsx` 支援。**
2.0 之後 `xlrd` **只讀 `.xls`**,拿它讀 `.xlsx` 會直接丟 `XLRDError`。所以一定要依副檔名選 engine,不能一招打天下。

**欄位型別在檔案之間會不一致,`concat` 之後變 `object`。**
同一個欄位在 A 檔是數字、B 檔因為有人打了「N/A」變成字串,合併後整欄變 `object`,Parquet 寫得出來但 Power BI 會當文字。彙整前先強制轉型:

```python
for col in ("流量", "誤差", "溫度"):
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors="coerce")   # 轉不動的變 NaN
```

**副檔名會騙人。**
有些「`.xls`」其實是別人另存的 XML 或 HTML 表格,`xlrd` 會丟 `Unsupported format`。所以每個檔案都要包 `try/except` 並印出跳過清單,不要讓一個壞檔擋掉整批。真的遇到 HTML 偽裝的,`pd.read_html(path)` 通常救得回來。

**Parquet 壓縮選 `zstd` 不要選 `snappy`。**
同一份資料 zstd 大約小 30–40%,解壓速度差異在這個規模下感覺不出來。

**不要用 `df.append` 在迴圈裡累加。**
那是 O(n²),400 個檔案會慢到懷疑人生(而且 pandas 2.0 已移除)。收集成 list 最後一次 `pd.concat`。
