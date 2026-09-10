# 依範本批次產生檢驗表

食譜說明:<https://loin123-rgb.github.io/dev-cookbook/recipes/excel/batch-fill-template/>

```bash
pip install -r requirements.txt
python fill_template.py --template templates/IQC.xlsm --data items.sample.csv --out out/
```

修改 `fill_template.py` 最上面的 `MAPPING`,把 CSV 欄名對到你範本裡的儲存格位址。
