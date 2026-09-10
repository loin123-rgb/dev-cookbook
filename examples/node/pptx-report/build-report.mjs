/**
 * 從 CSV 產生 PowerPoint 檢驗月報。
 *
 *   node build-report.mjs --data sample-data.csv --out out/月報.pptx
 */
import { readFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { parseArgs } from "node:util";
import PptxGenJS from "pptxgenjs";

const NAVY = "1F3864";
const RED = "C00000";
const GREY = "D9D9D9";
const NG_THRESHOLD = 0.05; // 不良率超過就標紅
const ROWS_PER_SLIDE = 12; // 表格不會自動分頁,超過會被靜靜切掉

const { values: opts } = parseArgs({
  options: {
    data: { type: "string", default: "sample-data.csv" },
    out: { type: "string", default: "out/report.pptx" },
    title: { type: "string", default: "進料檢驗月報" },
    period: { type: "string", default: "2026 Q1" },
  },
});

/** 極簡 CSV 解析:不處理引號內逗號,自家報表夠用。 */
async function readCsv(path) {
  const text = await readFile(path, "utf8");
  const [head, ...lines] = text.replace(/^﻿/, "").trim().split(/\r?\n/);
  const cols = head.split(",").map((c) => c.trim());
  return lines
    .filter((l) => l.trim())
    .map((line) => Object.fromEntries(line.split(",").map((v, i) => [cols[i], v.trim()])));
}

function summarise(rows) {
  const bySupplier = new Map();
  for (const r of rows) {
    const key = r.供應商;
    const acc = bySupplier.get(key) ?? { supplier: key, lots: 0, ng: 0 };
    acc.lots += 1;
    if (r.判定 !== "合格") acc.ng += 1;
    bySupplier.set(key, acc);
  }
  return [...bySupplier.values()]
    .map((s) => ({ ...s, rate: s.lots ? s.ng / s.lots : 0 }))
    .sort((a, b) => b.rate - a.rate);
}

function buildMaster(pptx, title) {
  pptx.defineSlideMaster({
    title: "MAIN",
    background: { color: "FFFFFF" },
    objects: [
      { rect: { x: 0, y: 0, w: "100%", h: 0.55, fill: { color: NAVY } } },
      {
        text: {
          text: title,
          options: {
            x: 0.35, y: 0, w: 6, h: 0.55,
            color: "FFFFFF", fontSize: 16, bold: true, valign: "middle",
          },
        },
      },
    ],
    slideNumber: { x: 9.3, y: 5.25, color: "888888", fontSize: 10 },
  });
}

function addCover(pptx, title, period, rows) {
  const s = pptx.addSlide();
  s.background = { color: NAVY };
  s.addText(title, {
    x: 0.8, y: 1.9, w: 8.4, h: 0.9,
    fontSize: 40, bold: true, color: "FFFFFF",
  });
  s.addText(`${period}　·　共 ${rows.length} 批`, {
    x: 0.8, y: 2.9, w: 8.4, h: 0.5,
    fontSize: 18, color: "AEC3E8",
  });
  s.addText(`產出時間 ${new Date().toISOString().slice(0, 16).replace("T", " ")}`, {
    x: 0.8, y: 4.7, w: 8.4, h: 0.3,
    fontSize: 11, color: "8FA8D4",
  });
}

function addSummaryTable(pptx, summary) {
  const header = ["供應商", "批數", "不良批", "不良率"].map((t) => ({
    text: t,
    options: { bold: true, color: "FFFFFF", fill: { color: NAVY }, align: "center" },
  }));

  const body = summary.map((r) => [
    r.supplier,
    { text: String(r.lots), options: { align: "right" } },
    { text: String(r.ng), options: { align: "right" } },
    {
      text: `${(r.rate * 100).toFixed(1)}%`,
      options: {
        align: "right",
        color: r.rate > NG_THRESHOLD ? RED : "333333",
        bold: r.rate > NG_THRESHOLD,
      },
    },
  ]);

  for (let i = 0; i < body.length; i += ROWS_PER_SLIDE) {
    const page = Math.floor(i / ROWS_PER_SLIDE) + 1;
    const pages = Math.ceil(body.length / ROWS_PER_SLIDE);
    const s = pptx.addSlide({ masterName: "MAIN" });
    s.addText(`供應商不良率彙總${pages > 1 ? `(${page}/${pages})` : ""}`, {
      x: 0.35, y: 0.8, w: 9.3, h: 0.5, fontSize: 24, bold: true,
    });
    s.addTable([header, ...body.slice(i, i + ROWS_PER_SLIDE)], {
      x: 0.35, y: 1.4, w: 9.3,
      colW: [3.3, 2.0, 2.0, 2.0],
      fontSize: 12, rowH: 0.32, valign: "middle",
      border: { type: "solid", color: GREY, pt: 0.5 },
    });
    s.addNotes(`不良率超過 ${(NG_THRESHOLD * 100).toFixed(0)}% 以紅色標示。`);
  }
}

function addChart(pptx, summary) {
  const s = pptx.addSlide({ masterName: "MAIN" });
  s.addText("不良率排行", { x: 0.35, y: 0.8, w: 9.3, h: 0.5, fontSize: 24, bold: true });
  // addChart 產的是原生 PowerPoint 圖表,收到的人可以點進去改資料
  s.addChart(
    pptx.ChartType.bar,
    [{
      name: "不良率 (%)",
      labels: summary.map((r) => r.supplier),
      values: summary.map((r) => Number((r.rate * 100).toFixed(2))),
    }],
    {
      x: 0.35, y: 1.4, w: 9.3, h: 3.5,
      barDir: "col",
      chartColors: [NAVY],
      showValue: true,
      valAxisTitle: "不良率 (%)",
      showLegend: false,
      catAxisLabelFontSize: 11,
    },
  );
}

async function main() {
  const rows = await readCsv(opts.data);
  if (!rows.length) {
    console.error(`${opts.data} 沒有任何資料列`);
    process.exit(2);
  }
  const summary = summarise(rows);

  const pptx = new PptxGenJS();
  pptx.layout = "LAYOUT_16x9"; // 10 × 5.625 英吋 —— 座標單位是英吋不是像素
  pptx.theme = { bodyFontFace: "微軟正黑體", headFontFace: "微軟正黑體" };
  pptx.author = "dev-cookbook";
  pptx.title = opts.title;

  buildMaster(pptx, opts.title);
  addCover(pptx, opts.title, opts.period, rows);
  addSummaryTable(pptx, summary);
  addChart(pptx, summary);

  await mkdir(dirname(opts.out), { recursive: true }); // writeFile 不會自己建目錄
  await pptx.writeFile({ fileName: opts.out }); // 一定要 await,不然可能寫出 0 byte
  console.log(`完成:${summary.length} 家供應商 / ${rows.length} 批 → ${opts.out}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
