# 清理有合併儲存格的髒表

食譜說明:<https://loin123-rgb.github.io/dev-cookbook/recipes/excel/clean-messy-sheet/>

```bash
pip install -r requirements.txt
python clean.py --src 月報.xlsx --header-rows 2 --ffill 供應商 --numeric 外觀_合格,外觀_不合格
```

不給 `--skip-top` 會自動偵測表頭在第幾列。先不帶 `--out` 跑一次看預覽,確認欄名對了再輸出。
