---
title: 輪詢暫存器並寫成 CSV
parent: Modbus 與儀器
grand_parent: 食譜
nav_order: 1
permalink: /recipes/modbus/read-registers-to-csv/
---

# 輪詢暫存器並寫成 CSV
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/python/modbus_logger/`](https://github.com/loin123-rgb/dev-cookbook/tree/main/examples/python/modbus_logger)

## 問題

要從一台 Modbus TCP 電表每秒撈一次電流值,連續記錄一週。難的不是「讀得到」——`pymodbus` 十行就讀得到。難的是**跑到第三天網路抖一下,程式掛了,而你星期一才發現**。

## 最小可用版本

```python
from pymodbus.client import ModbusTcpClient

client = ModbusTcpClient("192.168.1.50", port=502, timeout=3)
client.connect()

rr = client.read_holding_registers(address=0, count=6, slave=1)
if not rr.isError():
    print(rr.registers)          # [1234, 0, 1198, 0, 1256, 0]

client.close()
```

`pymodbus` 3.x 起參數叫 `slave`(舊版是 `unit`),而且 `read_holding_registers` 回傳的物件要用 `.isError()` 判斷,**它失敗時不會丟例外**。

## 能跑一週的版本

三個必要條件:

### 一、每次讀取都可能失敗,不能讓它終止迴圈

```python
def read_with_retry(client, addr, count, slave, retries=3):
    for attempt in range(retries):
        try:
            rr = client.read_holding_registers(address=addr, count=count, slave=slave)
            if not rr.isError():
                return rr.registers
            log.warning("讀取錯誤 %s (第 %d 次)", rr, attempt + 1)
        except ModbusException as e:
            log.warning("連線例外 %s (第 %d 次)", e, attempt + 1)
        time.sleep(0.5 * (attempt + 1))     # 退避
        client.connect()                     # 斷線就重連
    return None                              # 三次都失敗 → 這筆記 NaN,繼續跑
```

### 二、每筆都要 flush,不要等程式結束才寫檔

```python
with open(out, "a", newline="", encoding="utf-8-sig") as f:
    writer = csv.writer(f)
    while True:
        regs = read_with_retry(...)
        writer.writerow([datetime.now().isoformat(timespec="seconds"), *values])
        f.flush()          # 關鍵:斷電時已寫的資料才保得住
```

### 三、按日切檔

一週一個檔會變成幾百 MB、Excel 開不動。按日期切:

```python
def current_path(out_dir: Path) -> Path:
    return out_dir / f"current_{datetime.now():%Y%m%d}.csv"
```

每次寫入前比對檔名,換日就關舊檔開新檔並重寫表頭。

完整版(YAML 設定、SIGINT 優雅結束、統計輸出)在 [`logger.py`](https://github.com/loin123-rgb/dev-cookbook/blob/main/examples/python/modbus_logger/logger.py)。

```bash
pip install pymodbus pyyaml
python logger.py --config config.yaml
```

## 設定檔長這樣

```yaml
device:
  host: 192.168.1.50
  port: 502
  slave: 1
  timeout: 3

poll:
  interval_sec: 1.0
  registers:
    - {name: 電流_L1, address: 0, type: float32, word_order: big, scale: 1.0}
    - {name: 電流_L2, address: 2, type: float32, word_order: big, scale: 1.0}
    - {name: 電壓_L1, address: 8, type: uint16,  scale: 0.1}

output:
  dir: ./out
  rotate: daily
```

把暫存器位址寫在設定檔而不是程式裡,換一台機器就不用改程式。數值怎麼解碼見 [解碼 32-bit 浮點數與縮放值](../decode-registers/)。

## 踩過的坑

**`time.sleep(interval)` 會漂移。**
每輪讀取本身要花 20–80 ms,累積下來一天會少掉好幾百筆。要用「對齊絕對時間」的睡法:

```python
next_at = time.monotonic()
while running:
    do_one_poll()
    next_at += interval
    delay = next_at - time.monotonic()
    if delay > 0:
        time.sleep(delay)
    else:
        next_at = time.monotonic()      # 落後太多就重新對齊,不要瘋狂補跑
```

用 `time.monotonic()` 不用 `time.time()`——後者會被 NTP 校時往回調,算出負數。

**`read_holding_registers` 一次最多 125 個暫存器。**
Modbus 協定上限。要讀更多就分批,而且**不要為了省事一次讀 0~125 把不存在的位址包進去**,很多裝置會直接回 Illegal Data Address 讓整批失敗。

**功能碼 3 和 4 是不同的東西。**
`read_holding_registers` 是 FC3(4x 位址),`read_input_registers` 是 FC4(3x 位址)。手冊寫「30001」是 input register,要用 FC4;寫「40001」才是 holding。讀錯功能碼通常回 Illegal Data Address,不會回錯的值——算是萬幸。

**位址要不要減一,看手冊。**
手冊上的「40001」對應到 `address=0`。但有些廠商手冊直接寫「Address 0」,那就真的是 0。**讀到一個明顯不對的值時,先試 ±1。**

**Ctrl+C 要接。**
不接的話最後一筆可能沒 flush,而且 socket 沒關閉,有些裝置會佔著連線不放到 timeout,重跑會連不上:

```python
import signal
running = True
signal.signal(signal.SIGINT, lambda *_: globals().__setitem__("running", False))
```

**同一台裝置不要開兩支程式輪詢。**
很多低階 Modbus TCP 閘道器只支援單一連線,第二支連上去會把第一支踢掉,然後兩支互踢。
