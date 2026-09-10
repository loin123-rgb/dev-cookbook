---
title: 解碼 32-bit 浮點數與縮放值
parent: Modbus 與儀器
grand_parent: 食譜
nav_order: 2
permalink: /recipes/modbus/decode-registers/
---

# 解碼 32-bit 浮點數與縮放值
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/python/modbus_logger/decode.py`](https://github.com/loin123-rgb/dev-cookbook/blob/main/examples/python/modbus_logger/decode.py)

## 問題

Modbus 的暫存器只有一種型別:**16-bit 無號整數**。任何比它大的東西——32-bit 浮點數、32-bit 整數、64-bit——都是廠商自己把值拆成好幾個暫存器塞進去的。手冊上寫「Float32」,你讀到的是兩個看不懂的數字:

```
read_holding_registers(0, 2) → [17244, 19661]     # 這是 220.3 V
```

拼錯順序就會得到 `1.07617e+08` 這種一看就知道錯了的值,或更糟——**看起來很合理但其實是錯的值**。

## 四種可能的順序

把兩個暫存器攤成 4 個位元組 `A B C D`(A 是最高位),四種常見排法就是它們的排列組合:

| 排法 | 別稱 | 常見於 |
|:--|:--|:--|
| `ABCD` | Big-endian、High word first | Modbus 標準,最常見 |
| `CDAB` | Word swap、Low word first、Mid-little | **台系電表與 PLC 很常見** |
| `BADC` | Byte swap、Mid-big | 少數 RTU 閘道器 |
| `DCBA` | Little-endian | 罕見 |

沒有辦法從資料本身推斷,只能查手冊或試。

## 通用解碼函式

不要用 `pymodbus` 的 payload builder(3.x 各版本 API 一直變,而且已標記 deprecated)。直接用標準函式庫 `struct`:

```python
import struct

# 值是「輸出的第 n 個位元組要取原始的第幾個」
_PERMUTATIONS = {
    "abcd": (0, 1, 2, 3),
    "cdab": (2, 3, 0, 1),
    "badc": (1, 0, 3, 2),
    "dcba": (3, 2, 1, 0),
}

_ALIASES = {
    "big": "abcd", "high_word_first": "abcd",
    "little": "dcba",
    "word_swap": "cdab", "low_word_first": "cdab",
    "byte_swap": "badc",
}


def _arrange(regs: list[int], order: str) -> bytes:
    """把暫存器攤成位元組後依 order 重排(每 4 位元組一組)。"""
    raw = struct.pack(f">{len(regs)}H", *regs)
    perm = _PERMUTATIONS[_ALIASES.get(order.lower(), order.lower())]
    out = bytearray(len(raw))
    for base in range(0, len(raw), 4):
        for i, src in enumerate(perm):
            out[base + i] = raw[base + src]
    return bytes(out)


def regs_to_float32(regs: list[int], order: str = "big") -> float:
    return struct.unpack(">f", _arrange(regs, order))[0]


def regs_to_int32(regs: list[int], order: str = "big", signed: bool = True) -> int:
    value = struct.unpack(">I", _arrange(regs, order))[0]
    if signed and value >= 0x8000_0000:
        value -= 0x1_0000_0000
    return value


def reg_to_int16(reg: int, signed: bool = True) -> int:
    return reg - 0x1_0000 if signed and reg >= 0x8000 else reg
```

**先重排位元組、再統一用大端解讀**,四種排法才會得到四個真正不同的結果。

用 `struct` 的大小端旗標去疊加 word swap 是很自然的寫法,但 little-endian 的解讀會把 word swap 抵消掉——你會發現 ABCD 和 DCBA 解出一模一樣的值,四種變兩種,然後在那邊懷疑人生。先排位元組再固定用 `>` 解讀就沒這個問題。
{: .warning }

## 不確定順序時,四種都印出來

除錯神器:

```python
def try_all(regs: list[int]) -> dict[str, float]:
    return {name: struct.unpack(">f", _arrange(regs, name))[0] for name in _PERMUTATIONS}
```

```console
$ python decode.py 17244 19661
暫存器 [17244, 19661] 的四種 float32 解法:
  ABCD   =              220.3
  CDAB   =        1.07617e+08
  BADC   =        2.20453e+17
  DCBA   =       -2.14287e+08
```

一眼就知道是 ABCD。**記得把答案寫回設定檔,不要每次現場試。**

## 整數 + 縮放係數

比 float32 更常見的做法:用 16-bit 整數存,再乘一個係數。手冊會寫「Unit: 0.1V」。

```python
voltage = reg_to_int16(regs[0]) * 0.1        # 2203 → 220.3
```

把型別與係數寫在設定裡而不是程式裡:

```yaml
registers:
  - {name: 電壓, address: 8,  type: int16,   scale: 0.1,  unit: V}
  - {name: 電流, address: 12, type: float32, word_order: big, unit: A}
  - {name: 電能, address: 20, type: uint32,  word_order: big, scale: 0.01, unit: kWh}
```

對應的分派函式與「每種型別佔幾個暫存器」對照表:

```python
REG_COUNT = {"int16": 1, "uint16": 1, "int32": 2, "uint32": 2, "float32": 2, "float64": 4}


def decode(regs: list[int], cfg: dict) -> float:
    kind, order = cfg["type"], cfg.get("word_order", "big")
    if kind == "int16":
        value = reg_to_int16(regs[0], signed=True)
    elif kind == "uint16":
        value = regs[0]
    elif kind in ("int32", "uint32"):
        value = regs_to_int32(regs, order, signed=(kind == "int32"))
    elif kind == "float32":
        value = regs_to_float32(regs, order)
    else:
        raise ValueError(f"未知型別:{kind}")
    return value * cfg.get("scale", 1.0)
```

`REG_COUNT` 讓輪詢端知道每個項目要讀幾個暫存器,設定檔就不用重複寫。

## 踩過的坑

**`scale` 用乘法不要用除法。**
手冊寫「0.1V」代表 `讀值 × 0.1`。但有些手冊寫「Scale: 10」,意思是 `讀值 ÷ 10`。設定檔統一存**乘數**,轉換在寫設定時做完,程式裡永遠是乘法——不然半年後你會忘記是哪一種。

**負數不處理會變成六萬多。**
溫度 -5.0°C 存成 int16 是 `0xFFCE` = 65486,乘 0.1 之後溫度圖表會出現 6548.6 度。**看到「大概六萬多」的異常值,九成是漏了有號轉換。**

**32-bit 值跨兩個暫存器,要一次讀完。**
分兩次 `read_holding_registers(0, 1)` 和 `(1, 1)`,中間值可能剛好變動,你會拼出一個從未存在過的數字。一定要 `read_holding_registers(0, 2)` 一次拿。

**float32 精度只有約 7 位有效數字。**
累積電能到了 `12345678.9 kWh` 時 float32 存不下,末位會跳動。這是裝置端的限制不是你的 bug——遇到就改讀廠商提供的 uint32 + scale 版本暫存器(通常會有)。

**同一台裝置的不同欄位可能用不同順序。**
真的遇過:電流是 ABCD,累積電能是 CDAB。所以 `word_order` 要能**逐欄**設定,不要做成全域參數。
