# 把幾百個 .xls 彙整成 Parquet

食譜說明:<https://loin123-rgb.github.io/dev-cookbook/recipes/excel/xls-to-parquet/>

```bash
pip install -r requirements.txt
python consolidate.py --src "D:\測試記錄\封存區" --out "D:\測試記錄\archive.parquet" --numeric 流量,誤差,溫度
```

Power BI 端接 Parquet 的 M 語法在食譜頁面。
