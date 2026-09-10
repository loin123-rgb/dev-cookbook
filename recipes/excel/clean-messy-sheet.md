---
title: 清理有合併儲存格的髒表
parent: Excel 與試算表
grand_parent: 食譜
nav_order: 3
permalink: /recipes/excel/clean-messy-sheet/
---

# 清理有合併儲存格的髒表
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/python/clean_sheet/`](https://github.com/loin123-rgb/dev-cookbook/tree/main/examples/python/clean_sheet)

## 問題

人手維護的 Excel 幾乎一定有這些特徵:

```
                                          ← 前面空三列放 logo
      2026 年 第一季 進料檢驗統計          ← 標題橫跨整列(合併格)
                                          
  供應商  │      外觀      │      尺寸      │  ← 第一層表頭(合併格)
          │  合格 │ 不合格 │  合格 │ 不合格 │  ← 第二層表頭
  ────────┼───────┼────────┼───────┼────────┤
   甲公司 │   48  │    2   │   50  │    0   │
          │   31  │    1   │   32  │    0   │  ← 供應商欄合併,只有第一列有值
   乙公司 │   22  │    0   │   22  │    0   │
  ────────┼───────┼────────┼───────┼────────┤
   合計   │  101  │    3   │  104  │    0   │  ← 最後有小計列
```

`pd.read_excel` 直接讀會得到一堆 `Unnamed: 3`、`NaN`,完全沒法用。

## 解法:四個動作

```python
import pandas as pd

def clean(path, sheet=0, header_rows=2, skip_top=3):
    df = pd.read_excel(
        path, sheet_name=sheet,
        skiprows=skip_top,                       # ① 丟掉標題區
        header=list(range(header_rows)),         # ② 多層表頭
    )

    # ③ 攤平 MultiIndex 欄名:("外觀", "合格") → "外觀_合格"
    df.columns = [
        "_".join(str(p) for p in col if not str(p).startswith("Unnamed")).strip("_")
        for col in df.columns
    ]

    # ④ 合併儲存格造成的空白往下補
    df["供應商"] = df["供應商"].ffill()

    return df
```

### 再把小計列踢掉

```python
df = df[~df["供應商"].astype(str).str.contains("合計|小計|總計|Total", na=False)]
df = df.dropna(how="all")                       # 全空列
df = df.loc[:, ~df.columns.str.match(r"^Unnamed|^$")]   # 全空欄
```

完整版(自動偵測表頭起始列)在 [`clean.py`](https://github.com/loin123-rgb/dev-cookbook/blob/main/examples/python/clean_sheet/clean.py)。

## 自動找表頭在第幾列

不想每個檔都手數 `skiprows`,可以先用 `header=None` 整張讀進來,找第一列「非空欄位數 ≥ 一半」的那列:

```python
raw = pd.read_excel(path, header=None)
threshold = raw.shape[1] // 2
header_row = next(
    i for i in range(len(raw))
    if raw.iloc[i].notna().sum() >= threshold
)
df = pd.read_excel(path, skiprows=header_row)
```

對格式浮動的月報表很有效。

## 踩過的坑

**合併儲存格只有左上角那格有值。**
Excel 顯示上跨了五列,實際資料裡只有第一列有值、其餘是 `NaN`。所以 `ffill()` 是必要的——但**只對該補的欄做**。整張 `df.ffill()` 會把數值欄的空白也填滿,製造假資料。

**`ffill()` 會把小計列的供應商也填進去。**
順序很重要:**先 `ffill`,再刪小計列**。反過來做的話小計那列的 `NaN` 已經被前一列填掉,就篩不出來了。

**表頭有換行和全形空白。**
「不合格\n數量」和「不 合格」是不同的字串。統一正規化:

```python
df.columns = (df.columns.str.replace(r"\s+", "", regex=True)
                        .str.replace("　", "", regex=False))   # 全形空白
```

**數字欄裡混著文字。**
「48」「48 pcs」「-」「N/A」會讓整欄變 `object`。統一處理:

```python
df[col] = pd.to_numeric(
    df[col].astype(str).str.replace(r"[^\d.\-]", "", regex=True).replace("", None),
    errors="coerce",
)
```

**日期欄可能是 Excel 序號。**
讀出來是 `45678` 這種整數。`pd.to_datetime(df[col], unit="D", origin="1899-12-30")` 轉回來(注意是 12-30 不是 12-31,Excel 有 1900 年閏年的歷史 bug)。
