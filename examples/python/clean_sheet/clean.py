"""把人手維護的髒 Excel 轉成乾淨的 DataFrame / CSV。

用法:
    python clean.py --src 月報.xlsx --out cleaned.csv --ffill 供應商
    python clean.py --src 月報.xlsx --out cleaned.csv --header-rows 2 --skip-top 3
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

import pandas as pd

SUBTOTAL_PATTERN = re.compile(r"合計|小計|總計|平均|total|subtotal", re.IGNORECASE)


def detect_header_row(path: Path, sheet: str | int = 0, max_scan: int = 30) -> int:
    """猜表頭在第幾列:第一個「非空欄位數 >= 總欄數一半」的列。"""
    raw = pd.read_excel(path, sheet_name=sheet, header=None, nrows=max_scan)
    threshold = max(2, raw.shape[1] // 2)
    for i in range(len(raw)):
        if raw.iloc[i].notna().sum() >= threshold:
            return i
    return 0


def flatten_columns(columns) -> list[str]:
    """MultiIndex 欄名攤平:("外觀", "合格") -> "外觀_合格"。"""
    if not isinstance(columns, pd.MultiIndex):
        return [normalize(str(c)) for c in columns]
    out = []
    for col in columns:
        parts = [str(p) for p in col if not str(p).startswith("Unnamed") and str(p) != "nan"]
        out.append(normalize("_".join(parts)))
    return out


def normalize(name: str) -> str:
    """去掉換行、半形/全形空白。「不合格\n數量」和「不 合格」要視為同一個。"""
    return re.sub(r"\s+", "", name).replace("　", "").strip("_")


def dedupe(names: list[str]) -> list[str]:
    """重複欄名補上 _2, _3,否則後續選欄會拿到 DataFrame 而不是 Series。"""
    seen: dict[str, int] = {}
    out = []
    for n in names:
        if n in seen:
            seen[n] += 1
            out.append(f"{n}_{seen[n]}")
        else:
            seen[n] = 1
            out.append(n)
    return out


def to_number(series: pd.Series) -> pd.Series:
    """「48 pcs」「-」「N/A」都變成數字或 NaN。"""
    cleaned = (series.astype(str)
                     .str.replace(r"[^\d.\-]", "", regex=True)
                     .replace({"": None, "-": None}))
    return pd.to_numeric(cleaned, errors="coerce")


def clean(
    path: Path,
    sheet: str | int = 0,
    header_rows: int = 1,
    skip_top: int | None = None,
    ffill_cols: list[str] | None = None,
    numeric_cols: list[str] | None = None,
    drop_subtotals: bool = True,
) -> pd.DataFrame:
    if skip_top is None:
        skip_top = detect_header_row(path, sheet)

    df = pd.read_excel(
        path,
        sheet_name=sheet,
        skiprows=skip_top,
        header=list(range(header_rows)) if header_rows > 1 else 0,
    )

    df.columns = dedupe(flatten_columns(df.columns))

    # 丟掉全空的列與欄
    df = df.dropna(how="all").dropna(axis=1, how="all")
    df = df.loc[:, ~df.columns.str.match(r"^(Unnamed.*|nan|)$")]

    # 順序很重要:先 ffill 把合併儲存格補起來,再刪小計列。
    # 反過來做的話小計列的空白已經被前一列填滿,就篩不出來了。
    for col in ffill_cols or []:
        if col in df.columns:
            df[col] = df[col].ffill()

    if drop_subtotals and len(df.columns):
        first = df.columns[0]
        mask = df[first].astype(str).str.contains(SUBTOTAL_PATTERN, na=False)
        df = df[~mask]

    for col in numeric_cols or []:
        if col in df.columns:
            df[col] = to_number(df[col])

    return df.reset_index(drop=True)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="清理有合併儲存格與多層表頭的 Excel")
    ap.add_argument("--src", type=Path, required=True)
    ap.add_argument("--out", type=Path, help="輸出 CSV,不給就只印出預覽")
    ap.add_argument("--sheet", default=0)
    ap.add_argument("--header-rows", type=int, default=1, help="表頭佔幾列")
    ap.add_argument("--skip-top", type=int, default=None,
                    help="表頭前有幾列垃圾;不給就自動偵測")
    ap.add_argument("--ffill", default="", help="需要向下補值的欄名(合併儲存格),逗號分隔")
    ap.add_argument("--numeric", default="", help="要強制轉數值的欄名,逗號分隔")
    ap.add_argument("--keep-subtotals", action="store_true", help="保留合計/小計列")
    args = ap.parse_args(argv)

    sheet: str | int = int(args.sheet) if str(args.sheet).isdigit() else args.sheet
    df = clean(
        args.src,
        sheet=sheet,
        header_rows=args.header_rows,
        skip_top=args.skip_top,
        ffill_cols=[c.strip() for c in args.ffill.split(",") if c.strip()],
        numeric_cols=[c.strip() for c in args.numeric.split(",") if c.strip()],
        drop_subtotals=not args.keep_subtotals,
    )

    print(f"清理後:{len(df):,} 列 × {df.shape[1]} 欄")
    print(f"欄位:{list(df.columns)}\n")
    print(df.head(10).to_string())

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(args.out, index=False, encoding="utf-8-sig")  # utf-8-sig 讓 Excel 開不亂碼
        print(f"\n已寫出 {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
