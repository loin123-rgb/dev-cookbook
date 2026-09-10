"""Modbus 暫存器解碼:16/32-bit 整數與 float32。

只用標準函式庫 struct,不依賴 pymodbus 的 payload API(它每個版本都在變)。

位元組順序的表示法:把兩個暫存器攤成 4 個位元組 A B C D(A 是最高位),
四種常見排法就是這四個字母的排列組合:

    ABCD  big-endian,Modbus 標準
    CDAB  word swap,台系電表 / PLC 很常見
    BADC  byte swap
    DCBA  little-endian(全反)
"""
from __future__ import annotations

import struct

# 每種型別佔幾個 16-bit 暫存器
REG_COUNT: dict[str, int] = {
    "int16": 1, "uint16": 1,
    "int32": 2, "uint32": 2, "float32": 2,
    "float64": 4,
}

# 4 位元組的排列:值是「輸出的第 n 個位元組要取原始的第幾個」
_PERMUTATIONS: dict[str, tuple[int, ...]] = {
    "abcd": (0, 1, 2, 3),
    "cdab": (2, 3, 0, 1),
    "badc": (1, 0, 3, 2),
    "dcba": (3, 2, 1, 0),
}

# 各家手冊/工具的別名對照
_ALIASES: dict[str, str] = {
    "big": "abcd", "big_endian": "abcd", "high_word_first": "abcd",
    "little": "dcba", "little_endian": "dcba",
    "word_swap": "cdab", "low_word_first": "cdab", "mid_little": "cdab",
    "byte_swap": "badc", "mid_big": "badc",
}


def resolve_order(order: str) -> tuple[int, ...]:
    """把 'big' / 'cdab' / 'word_swap' 之類的說法統一成位元組排列。"""
    key = str(order).strip().lower()
    key = _ALIASES.get(key, key)
    if key not in _PERMUTATIONS:
        raise ValueError(
            f"未知的位元組順序:{order}(可用:{', '.join(_PERMUTATIONS)} 或 {', '.join(_ALIASES)})"
        )
    return _PERMUTATIONS[key]


def _arrange(regs: list[int], order: str) -> bytes:
    """把 N 個暫存器攤成位元組後依 order 重排(每 4 位元組一組)。"""
    raw = struct.pack(f">{len(regs)}H", *regs)
    perm = resolve_order(order)
    out = bytearray(len(raw))
    for base in range(0, len(raw), 4):
        for i, src in enumerate(perm):
            out[base + i] = raw[base + src]
    return bytes(out)


def reg_to_int16(reg: int, signed: bool = True) -> int:
    """單一暫存器轉整數。忘記做有號轉換,-5.0°C 會變成 6548.6 度。"""
    return reg - 0x1_0000 if signed and reg >= 0x8000 else reg


def regs_to_int32(regs: list[int], order: str = "big", signed: bool = True) -> int:
    if len(regs) != 2:
        raise ValueError(f"int32 需要 2 個暫存器,拿到 {len(regs)}")
    value = struct.unpack(">I", _arrange(regs, order))[0]
    if signed and value >= 0x8000_0000:
        value -= 0x1_0000_0000
    return value


def regs_to_float32(regs: list[int], order: str = "big") -> float:
    if len(regs) != 2:
        raise ValueError(f"float32 需要 2 個暫存器,拿到 {len(regs)}")
    return struct.unpack(">f", _arrange(regs, order))[0]


def regs_to_float64(regs: list[int], order: str = "big") -> float:
    if len(regs) != 4:
        raise ValueError(f"float64 需要 4 個暫存器,拿到 {len(regs)}")
    # float64 的 4 個字:先把每 2 個字組成的 4 位元組群各自重排,再整體照順序組回去
    words = regs if resolve_order(order) in (_PERMUTATIONS["abcd"], _PERMUTATIONS["badc"]) else regs[2:] + regs[:2]
    return struct.unpack(">d", _arrange(words, order))[0]


def decode(regs: list[int], cfg: dict) -> float:
    """依設定解碼並套用縮放係數。

    cfg 需要 type,可選 word_order(預設 big)與 scale(預設 1.0)。
    scale 一律存「乘數」:手冊寫 Unit 0.1V 就填 0.1,寫 Scale 10 就填 0.1。
    """
    kind = cfg["type"]
    order = cfg.get("word_order", "big")

    if kind == "int16":
        value: float = reg_to_int16(regs[0], signed=True)
    elif kind == "uint16":
        value = regs[0]
    elif kind == "int32":
        value = regs_to_int32(regs, order, signed=True)
    elif kind == "uint32":
        value = regs_to_int32(regs, order, signed=False)
    elif kind == "float32":
        value = regs_to_float32(regs, order)
    elif kind == "float64":
        value = regs_to_float64(regs, order)
    else:
        raise ValueError(f"未知型別:{kind}(可用:{', '.join(REG_COUNT)})")

    return value * cfg.get("scale", 1.0)


def try_all(regs: list[int]) -> dict[str, float]:
    """不確定順序時,四種排法都解出來讓人眼挑合理的那個。"""
    return {name: struct.unpack(">f", _arrange(regs, name))[0] for name in _PERMUTATIONS}


if __name__ == "__main__":
    import sys

    if len(sys.argv) == 3:
        pair = [int(sys.argv[1]), int(sys.argv[2])]
    else:
        pair = [17244, 19661]
        print("(未給參數,用範例值 17244 19661)")

    print(f"暫存器 {pair} 的四種 float32 解法:")
    for name, value in try_all(pair).items():
        print(f"  {name.upper():6} = {value:>18.6g}")
