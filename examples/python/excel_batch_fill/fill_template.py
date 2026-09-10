"""依範本批次產生 Excel 檢驗表。

用法:
    python fill_template.py --template templates/IQC.xlsm --data items.csv --out out/

items.csv 需要有 header,欄名對應 MAPPING 的 key。
"""
from __future__ import annotations

import argparse
import csv
import re
import shutil
import sys
from pathlib import Path

import openpyxl

# CSV 欄名 -> 範本中的儲存格位址
MAPPING: dict[str, str] = {
    "品名": "C3",
    "料號": "F3",
    "供應商": "C4",
    "進料數量": "H3",  # 這格驅動抽樣計畫公式,填了 AC/RE 會自己算
    "檢驗日期": "F4",
}

INVALID_CHARS = re.compile(r'[\/:*?"<>|]')


def safe_name(text: str, limit: int = 100) -> str:
    """把字串變成合法的 Windows 檔名。"""
    return INVALID_CHARS.sub("_", str(text)).strip().rstrip(".")[:limit] or "untitled"


def fill_one(template: Path, out: Path, cells: dict[str, object]) -> None:
    """複製範本後只覆寫指定儲存格,巨集/驗證/公式全部保留。"""
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(template, out)

    keep_vba = template.suffix.lower() in {".xlsm", ".xltm"}
    # 注意:絕對不要傳 data_only=True,否則存檔時公式會被換成快取值
    wb = openpyxl.load_workbook(out, keep_vba=keep_vba)
    ws = wb.active
    for addr, value in cells.items():
        ws[addr] = value
    wb.save(out)
    wb.close()


def load_rows(data: Path) -> list[dict[str, str]]:
    with data.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="依範本批次產生 Excel 檢驗表")
    ap.add_argument("--template", type=Path, required=True, help="範本 .xlsm / .xlsx")
    ap.add_argument("--data", type=Path, required=True, help="資料 CSV(UTF-8)")
    ap.add_argument("--out", type=Path, default=Path("out"), help="輸出目錄")
    ap.add_argument("--name-cols", default="料號,品名",
                    help="用哪些欄位組成檔名,逗號分隔")
    ap.add_argument("--overwrite", action="store_true",
                    help="同名檔案直接覆蓋(預設是跳過,避免蓋掉已填好的檢驗結果)")
    args = ap.parse_args(argv)

    if not args.template.exists():
        print(f"找不到範本:{args.template}", file=sys.stderr)
        return 2

    rows = load_rows(args.data)
    if not rows:
        print("資料檔沒有任何列", file=sys.stderr)
        return 2

    name_cols = [c.strip() for c in args.name_cols.split(",") if c.strip()]
    suffix = args.template.suffix
    made = skipped = failed = 0

    for i, row in enumerate(rows, 1):
        stem = safe_name("_".join(str(row.get(c, "")) for c in name_cols))
        out = args.out / f"{stem}{suffix}"

        if out.exists() and not args.overwrite:
            print(f"  {i}/{len(rows)} [跳過已存在] {out.name}")
            skipped += 1
            continue

        cells = {addr: row[col] for col, addr in MAPPING.items() if col in row}
        try:
            fill_one(args.template, out, cells)
            print(f"  {i}/{len(rows)} {out.name}")
            made += 1
        except Exception as e:  # 單筆失敗不要擋掉整批
            print(f"  {i}/{len(rows)} [失敗] {out.name}: {e}", file=sys.stderr)
            failed += 1

    print(f"\n完成:產生 {made} 份,跳過 {skipped} 份,失敗 {failed} 份 → {args.out}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
