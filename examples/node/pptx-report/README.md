# 用 Node.js 批次產生 PowerPoint 報告

食譜說明:<https://loin123-rgb.github.io/dev-cookbook/recipes/report/pptx-report/>

```bash
npm install
npm run build
```

會在 `out/` 產生一份四頁的 `.pptx`:封面、彙總表(超過 12 列自動分頁)、原生長條圖。

換成自己的資料只要改 `sample-data.csv`,或用 `--data` 指定路徑:

```bash
node build-report.mjs --data D:\檢驗紀錄\2026Q2.csv --out out/Q2.pptx --period "2026 Q2"
```
