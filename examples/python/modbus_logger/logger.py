"""Modbus TCP 長時間記錄器:斷線自動重連、按日切檔、即時 flush。

用法:
    python logger.py --config config.yaml
    python logger.py --config config.yaml --once     # 只讀一次,用來驗設定
"""
from __future__ import annotations

import argparse
import csv
import logging
import signal
import sys
import time
from datetime import datetime
from pathlib import Path

import yaml
from pymodbus.client import ModbusTcpClient
from pymodbus.exceptions import ModbusException

from decode import REG_COUNT, decode

log = logging.getLogger("modbus_logger")
_running = True


def _stop(*_args) -> None:
    """Ctrl+C:設旗標讓主迴圈自己收尾,才能 flush 最後一筆並關閉 socket。"""
    global _running
    _running = False
    log.info("收到中斷訊號,收尾中...")


def read_with_retry(client: ModbusTcpClient, addr: int, count: int,
                    slave: int, retries: int = 3) -> list[int] | None:
    """讀不到就退避重試並重連。三次都失敗回 None,讓呼叫端記空值繼續跑。"""
    for attempt in range(1, retries + 1):
        try:
            rr = client.read_holding_registers(address=addr, count=count, slave=slave)
            if not rr.isError():          # 注意:失敗不會丟例外,要自己判斷
                return list(rr.registers)
            log.warning("位址 %d 讀取錯誤 %s(第 %d 次)", addr, rr, attempt)
        except ModbusException as e:
            log.warning("位址 %d 連線例外 %s(第 %d 次)", addr, e, attempt)

        if attempt < retries:
            time.sleep(0.5 * attempt)     # 線性退避
            try:
                client.connect()
            except Exception:
                pass
    return None


def current_path(out_dir: Path, rotate: str) -> Path:
    now = datetime.now()
    stamp = {"daily": f"{now:%Y%m%d}", "hourly": f"{now:%Y%m%d_%H}"}.get(rotate, "all")
    return out_dir / f"modbus_{stamp}.csv"


def poll_once(client: ModbusTcpClient, regs_cfg: list[dict], slave: int) -> list[object]:
    values: list[object] = []
    for cfg in regs_cfg:
        count = REG_COUNT[cfg["type"]]
        # 32-bit 值一定要一次讀完兩個字,分兩次讀可能拼出從未存在過的數字
        raw = read_with_retry(client, cfg["address"], count, slave)
        if raw is None:
            values.append("")             # CSV 裡留空,下游當缺值
            continue
        try:
            values.append(round(decode(raw, cfg), 4))
        except Exception as e:
            log.error("%s 解碼失敗 %s: %s", cfg["name"], raw, e)
            values.append("")
    return values


def run(cfg: dict, once: bool = False) -> int:
    dev = cfg["device"]
    poll = cfg["poll"]
    regs_cfg = poll["registers"]
    out_dir = Path(cfg["output"]["dir"])
    rotate = cfg["output"].get("rotate", "daily")
    interval = float(poll.get("interval_sec", 1.0))
    slave = dev.get("slave", 1)

    out_dir.mkdir(parents=True, exist_ok=True)
    header = ["時間", *[r["name"] for r in regs_cfg]]

    client = ModbusTcpClient(dev["host"], port=dev.get("port", 502),
                             timeout=dev.get("timeout", 3))
    if not client.connect():
        log.error("無法連線到 %s:%s", dev["host"], dev.get("port", 502))
        return 1
    log.info("已連線 %s:%s slave=%s", dev["host"], dev.get("port", 502), slave)

    path: Path | None = None
    fh = None
    writer = None
    n_ok = n_err = 0
    # 用 monotonic 對齊絕對時間,避免 sleep 累積漂移,也不受 NTP 校時影響
    next_at = time.monotonic()

    try:
        while _running:
            want = current_path(out_dir, rotate)
            if want != path:                       # 換日 -> 開新檔並重寫表頭
                if fh:
                    fh.close()
                is_new = not want.exists()
                fh = want.open("a", newline="", encoding="utf-8-sig")
                writer = csv.writer(fh)
                if is_new:
                    writer.writerow(header)
                path = want
                log.info("寫入 %s", path)

            values = poll_once(client, regs_cfg, slave)
            writer.writerow([datetime.now().isoformat(timespec="seconds"), *values])
            fh.flush()                             # 斷電時已寫的資料才保得住

            if any(v == "" for v in values):
                n_err += 1
            else:
                n_ok += 1

            if once:
                print(dict(zip(header, [datetime.now().isoformat(timespec="seconds"), *values])))
                break

            next_at += interval
            delay = next_at - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            else:
                next_at = time.monotonic()          # 落後太多就重新對齊,不要瘋狂補跑
    finally:
        if fh:
            fh.close()
        client.close()
        log.info("結束:成功 %d 筆,含錯誤 %d 筆", n_ok, n_err)

    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Modbus TCP 長時間記錄器")
    ap.add_argument("--config", type=Path, default=Path("config.yaml"))
    ap.add_argument("--once", action="store_true", help="只讀一次就結束,用來驗證設定")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        stream=sys.stderr,
    )
    signal.signal(signal.SIGINT, _stop)

    if not args.config.exists():
        log.error("找不到設定檔 %s(可從 config.example.yaml 複製)", args.config)
        return 2

    cfg = yaml.safe_load(args.config.read_text(encoding="utf-8"))
    return run(cfg, once=args.once)


if __name__ == "__main__":
    raise SystemExit(main())
