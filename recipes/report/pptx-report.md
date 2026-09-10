---
title: 用 Node.js 批次產生 PowerPoint 報告
parent: 報表產出
grand_parent: 食譜
nav_order: 1
permalink: /recipes/report/pptx-report/
---

# 用 Node.js 批次產生 PowerPoint 報告
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/node/pptx-report/`](https://github.com/loin123-rgb/dev-cookbook/tree/main/examples/node/pptx-report)

## 問題

測試資料整理完了,但主管要的是投影片。每次都要手工把表格貼進 PowerPoint、調欄寬、換色、加標題——一次二十分鐘,一個月做四次。

## 解法

`pptxgenjs` 純 JavaScript,不需要裝 PowerPoint,Windows / Linux / CI 都能跑。

```bash
npm init -y && npm pkg set type=module && npm i pptxgenjs
```

```javascript
import PptxGenJS from "pptxgenjs";

const pptx = new PptxGenJS();
pptx.layout = "LAYOUT_16x9";           // 10 x 5.625 英吋

// 定義母片,標題列與頁尾只寫一次
pptx.defineSlideMaster({
  title: "MAIN",
  background: { color: "FFFFFF" },
  objects: [
    { rect: { x: 0, y: 0, w: "100%", h: 0.55, fill: { color: "1F3864" } } },
    { text: {
        text: "進料檢驗月報",
        options: { x: 0.35, y: 0, w: 6, h: 0.55, color: "FFFFFF",
                   fontSize: 16, bold: true, valign: "middle" },
    }},
  ],
  slideNumber: { x: 9.3, y: 5.25, color: "888888", fontSize: 10 },
});

const slide = pptx.addSlide({ masterName: "MAIN" });
slide.addText("2026 Q1 不良率彙總", { x: 0.35, y: 0.8, fontSize: 24, bold: true });

await pptx.writeFile({ fileName: "out/月報.pptx" });
```

## 表格:第一列是表頭

`addTable` 吃的是二維陣列,每格可以是字串或帶樣式的物件。

```javascript
const header = ["供應商", "批數", "不良批", "不良率"].map((t) => ({
  text: t,
  options: { bold: true, color: "FFFFFF", fill: { color: "1F3864" }, align: "center" },
}));

const body = rows.map((r) => [
  r.supplier,
  { text: String(r.lots), options: { align: "right" } },
  { text: String(r.ng), options: { align: "right" } },
  { text: `${(r.rate * 100).toFixed(1)}%`,
    options: { align: "right",
               color: r.rate > 0.05 ? "C00000" : "333333",   // 超標標紅
               bold: r.rate > 0.05 } },
]);

slide.addTable([header, ...body], {
  x: 0.35, y: 1.4, w: 9.3,
  colW: [3.3, 2.0, 2.0, 2.0],
  fontSize: 12,
  border: { type: "solid", color: "D9D9D9", pt: 0.5 },
  rowH: 0.32,
  valign: "middle",
});
```

## 圖表

`pptxgenjs` 產的是**原生 PowerPoint 圖表**,不是圖片——收到的人可以點進去改資料、換樣式。

```javascript
slide.addChart(pptx.ChartType.bar, [{
  name: "不良率",
  labels: rows.map((r) => r.supplier),
  values: rows.map((r) => +(r.rate * 100).toFixed(2)),
}], {
  x: 0.35, y: 1.4, w: 9.3, h: 3.6,
  barDir: "col",
  chartColors: ["4472C4"],
  showValue: true,
  valAxisTitle: "不良率 (%)",
  showLegend: false,
});
```

## 一份資料一頁,批次跑

```javascript
for (const [supplier, records] of Object.entries(grouped)) {
  const s = pptx.addSlide({ masterName: "MAIN" });
  s.addText(supplier, { x: 0.35, y: 0.8, fontSize: 22, bold: true });
  s.addTable(buildTable(records), { x: 0.35, y: 1.4, w: 9.3, fontSize: 11 });
  s.addNotes(`資料期間 ${period},共 ${records.length} 批。`);   // 講稿備忘稿
}
```

完整版(讀 CSV、分組、封面頁、圖表頁)在 [`build-report.mjs`](https://github.com/loin123-rgb/dev-cookbook/blob/main/examples/node/pptx-report/build-report.mjs)。

```bash
node build-report.mjs --data sample-data.csv --out out/月報.pptx
```

## 踩過的坑

**單位是英吋不是像素。**
`LAYOUT_16x9` 是 10 × 5.625 英吋。`x: 100` 會把物件丟到畫面外一百英吋處,而且**不會報錯**——你只會得到一張空白投影片。座標一律用小數。

**中文字型要明確指定。**
不指定的話在對方電腦上會 fallback 成 Calibri,中文變成方框或明體。全域設定:

```javascript
pptx.theme = { bodyFontFace: "微軟正黑體", headFontFace: "微軟正黑體" };
```
給外部客戶的話用「Microsoft JhengHei」,英文名在非中文版 Office 上比較保險。

**`writeFile` 是 async,一定要 await。**
少了 `await`,Node 可能在檔案寫完前就退出,你會得到一個 0 byte 或損毀的 `.pptx`。

**輸出目錄不存在不會自動建立。**
`writeFile` 直接丟 `ENOENT`。先 `await fs.mkdir(dirname(out), { recursive: true })`。

**表格太長不會自動分頁。**
超過投影片高度的部分直接被切掉,一樣不報錯。自己算:一頁大約放 12–14 列(`rowH: 0.32`),超過就分頁:

```javascript
const PER_PAGE = 12;
for (let i = 0; i < body.length; i += PER_PAGE) {
  const s = pptx.addSlide({ masterName: "MAIN" });
  s.addTable([header, ...body.slice(i, i + PER_PAGE)], { /* ... */ });
}
```

**顏色不要加 `#`。**
`color: "#C00000"` 會被當成無效值靜靜忽略,寫 `"C00000"`。
