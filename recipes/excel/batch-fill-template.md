---
title: 依範本批次產生檢驗表
parent: Excel 與試算表
grand_parent: 食譜
nav_order: 1
permalink: /recipes/excel/batch-fill-template/
---

# 依範本批次產生檢驗表
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/python/excel_batch_fill/`](https://github.com/loin123-rgb/dev-cookbook/tree/main/examples/python/excel_batch_fill)

## 問題

手上有一份設計好的 `.xlsm` 檢驗表範本:表頭有公司格式、欄位有下拉選單、抽樣數量欄位有公式會自動帶出 AC/RE 值。現在有 300 筆料號要各產生一份,每份只有「品名、料號、供應商、數量」不一樣。

手動另存新檔 300 次不是辦法。

## 為什麼不能直接用 openpyxl 從零建立

因為範本裡有三樣東西 `openpyxl` **建不出來也保不住**:

| 元素 | openpyxl 讀寫 | 說明 |
|:--|:--|:--|
| VBA 巨集 | 需 `keep_vba=True` | 否則另存後 `.xlsm` 變成沒有巨集的空殼 |
| 資料驗證(下拉選單) | 部分會掉 | 尤其是參照其他工作表的清單來源 |
| 條件式格式、樞紐、圖表 | 常掉 | 重建成本很高 |

所以正確做法是:**不要重建,用複製的。** 把範本檔整份 `shutil.copy` 出來,只打開副本改那幾格值。

## 解法

```python
import shutil
from pathlib import Path
import openpyxl

def fill_one(template: Path, out: Path, cells: dict[str, object]) -> None:
    """複製範本後只覆寫指定儲存格,其餘結構原封不動。"""
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(template, out)                       # 關鍵:先複製

    wb = openpyxl.load_workbook(out, keep_vba=True)  # 關鍵:保住巨集
    ws = wb.active
    for addr, value in cells.items():
        ws[addr] = value
    wb.save(out)
    wb.close()
```

呼叫端把每一列資料對應到儲存格位址:

```python
fill_one(
    template=Path("templates/IQC_檢驗表.xlsm"),
    out=Path(f"out/{row['料號']}_{row['品名']}.xlsm"),
    cells={
        "C3": row["品名"],
        "F3": row["料號"],
        "C4": row["供應商"],
        "H3": row["進料數量"],   # 這格會驅動抽樣計畫公式
    },
)
```

完整版(讀 CSV 清單、檔名淨化、進度輸出)在 [`fill_template.py`](https://github.com/loin123-rgb/dev-cookbook/blob/main/examples/python/excel_batch_fill/fill_template.py)。

## 讓公式自動算,不要自己算

範本裡如果已經有這種公式:

```
' 檢驗數量 = 依 $H$3(進料數量)查抽樣計畫表
=INDEX(抽樣計畫!$C:$C, MATCH($H$3, 抽樣計畫!$A:$A, 1))
```

那你只要填 `H3`,檢驗數量、AC、RE 全部會自己跳出來。**把邏輯留在 Excel 裡,Python 只負責填輸入值**,這樣日後品保要改抽樣規則,不用來找你改程式。

## 踩過的坑

**`load_workbook` 預設會把公式讀成值。**
`load_workbook(path)` 預設 `data_only=False`,讀到的是公式字串,存回去沒問題。但如果你寫了 `data_only=True`,存檔時**所有公式會被換成當下的快取值**,範本就毀了。批次填表永遠不要開 `data_only`。

**沒有 `keep_vba=True`,`.xlsm` 存完會壞。**
Excel 開起來會跳「發現無法讀取的內容」,而且巨集消失。

**openpyxl 存檔後下拉選單可能不見。**
如果驗證來源是「參照另一個工作表的具名範圍」,存回去有機率掉。驗證方式:產一份出來,實際用 Excel 開,點那格看有沒有箭頭。若真的掉了,退路是改用 `xlwings` 驅動真正的 Excel(需要裝 Excel,但 100% 保真):

```python
import xlwings as xw

with xw.App(visible=False) as app:
    wb = app.books.open(str(template))
    wb.sheets[0].range("C3").value = row["品名"]
    wb.save(str(out))
    wb.close()
```
代價是慢很多(每份約 0.5–2 秒 vs openpyxl 的 0.05 秒),300 份要跑幾分鐘。**先用 openpyxl,驗證掉了才換 xlwings。**

**檔名會炸。**
料號常有 `/`、`:`、`*`,直接當檔名會 `OSError`。一定要過濾:

```python
import re
safe = re.sub(r'[\/:*?"<>|]', "_", name).strip()[:100]
```

**輸出目錄要先確認是空的。**
批次腳本重跑時會覆蓋。範例腳本加了 `--overwrite` 旗標,沒帶就遇到同名檔案直接跳過,避免不小心蓋掉已經填好檢驗結果的檔案。
