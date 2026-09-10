"""把一整個資料夾的 Excel(含舊 .xls)彙整成單一 Parquet。

用法:
    python consolidate.py --src "D:\封存區" --out archive.parquet
    python consolidate.py --src "D:\封存區" --out archive.parquet --numeric 流量,誤差,溫度
"""
from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import pandas as pd

EXCEL_SUFFIXES = {".xls", ".xlsx", ".xlsm"}


def read_any_excel(path: Path, sheet: str | int = 0) -> pd.DataFrame:
    """依副檔名選 engine。xlrd 2.x 只讀得了 .xls。"""
    engine = "xlrd" if path.suffix.lower() == ".xls" else "openpyxl"
    try:
        df = pd.read_excel(path, sheet_name=sheet, engine=engine)
    except Exception:
        # 有些「.xls」其實是別人另存的 HTML 表格,read_html 通常救得回來
        if path.suffix.lower() == ".xls":
            tables = pd.read_html(path)
            if not tables:
                raise
            df = tables[0]
        else:
            raise

    df["來源檔"] = path.name
    # fromtimestamp 給的是本機時間;pd.Timestamp(..., unit="s") 會給 UTC,對帳時會差 8 小時
    df["來源修改時間"] = datetime.fromtimestamp(path.stat().st_mtime)
    return df


def coerce_numeric(df: pd.DataFrame, columns: list[str]) -> pd.DataFrame:
    """把指定欄強制轉數值,轉不動的變 NaN。

    不做這步的話,同一欄在不同檔案裡型別不一致,concat 後整欄會變 object,
    Power BI 會把它當文字。
    """
    for col in columns:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def consolidate(
    src: Path,
    out: Path,
    numeric_cols: list[str],
    sheet: str | int = 0,
    workers: int = 4,
) -> int:
    files = sorted(p for p in src.rglob("*") if p.suffix.lower() in EXCEL_SUFFIXES
                   and not p.name.startswith("~$"))   # 排除 Excel 開啟中的暫存檔
    if not files:
        print(f"在 {src} 底下找不到任何 Excel 檔", file=sys.stderr)
        return 2

    print(f"找到 {len(files)} 個檔案,開始讀取...")
    started = time.monotonic()
    frames: list[pd.DataFrame] = []
    skipped: list[tuple[str, str]] = []

    # Excel 解析主要是 CPU + IO 混合,執行緒能拿到部分好處且不用處理 pickling
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(read_any_excel, f, sheet): f for f in files}
        for i, fut in enumerate(as_completed(futures), 1):
            f = futures[fut]
            try:
                frames.append(coerce_numeric(fut.result(), numeric_cols))
            except Exception as e:
                skipped.append((f.name, str(e)[:120]))
            if i % 25 == 0 or i == len(files):
                print(f"  {i}/{len(files)}")

    if not frames:
        print("所有檔案都讀取失敗", file=sys.stderr)
        return 1

    big = pd.concat(frames, ignore_index=True)   # 不要在迴圈裡 append,那是 O(n^2)
    out.parent.mkdir(parents=True, exist_ok=True)
    big.to_parquet(out, engine="pyarrow", compression="zstd", index=False)

    elapsed = time.monotonic() - started
    size_mb = out.stat().st_size / 1e6
    print(f"\n完成:{len(big):,} 列 × {big.shape[1]} 欄 → {out} ({size_mb:.1f} MB)")
    print(f"耗時 {elapsed:.1f} 秒,成功 {len(frames)} 檔,跳過 {len(skipped)} 檔")

    if skipped:
        print("\n跳過的檔案:")
        for name, why in skipped:
            print(f"  - {name}: {why}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="把資料夾內的 Excel 彙整成 Parquet")
    ap.add_argument("--src", type=Path, required=True, help="來源資料夾(會遞迴搜尋)")
    ap.add_argument("--out", type=Path, required=True, help="輸出 .parquet")
    ap.add_argument("--sheet", default=0, help="工作表名稱或索引,預設第一個")
    ap.add_argument("--numeric", default="",
                    help="要強制轉數值的欄名,逗號分隔")
    ap.add_argument("--workers", type=int, default=4, help="平行讀取執行緒數")
    args = ap.parse_args(argv)

    sheet: str | int = int(args.sheet) if str(args.sheet).isdigit() else args.sheet
    numeric_cols = [c.strip() for c in args.numeric.split(",") if c.strip()]
    return consolidate(args.src, args.out, numeric_cols, sheet, args.workers)


if __name__ == "__main__":
    raise SystemExit(main())
