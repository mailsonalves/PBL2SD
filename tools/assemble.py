#!/usr/bin/env python3
"""Assemble the PBL2 32-bit ISA without external dependencies.

Syntax: MNEMONIC operand, operand; commas are optional. Registers r0..r15,
case-insensitive identifiers, decimal/0x hex integers, and ;/#// comments.
Labels resolve absolute word addresses for JMP/JZ/JNZ. MOVI is unsigned16;
ADDI accepts signed16. All field ranges are checked rather than truncated.

Graphics immediates:
  CLEAR; PALETTE address,rgb565; TILE x,y,tile; SCROLL x,y; BIRD_Y y
  TRI1 x,y; TRI2 x,y; TRI3 x,y,color; RECT x0,y0,x1,y1,color
  SPR_POS id,x,y; SPR_ATTR id,tile,enable,flipH,flipV
  SPR_STYLE id,priority,palette_enable,bank; BUFFER_CONFIG enable; PRESENT
The full legacy names from README.md are aliases for these same operations.
Register graphics append R: SCROLLR rx,ry; SPR_POSR id,rx,ry;
TRI1R rx,ry; TRI2R rx,ry; TRI3R rx,ry,rcolor; TILER rx,ry,rtile;
PALETTER raddress,rrgb565; SPR_ATTRR id,rtile,rflags (enable,H,V bits2..0);
SPR_STYLER id,rpriority,rbank (palette_enable bit4,bank bits3..0).
EMIT rsource forwards a complete legacy graphics word. RECTR rx0,ry0,rx1,
ry1,rcolor expands to two triangles without modifying registers.
RECT requires positive area. A zero-area RECTR draws nothing, following the
existing triangle rasterizer; both forms use inclusive corner coordinates.

ALU: MOVI rd,u16; MOV rd,ra; ADD/SUB/AND/OR/XOR/SHL/SHR rd,ra,rb;
CMP ra,rb; ADDI rd,ra,s16. Flow: NOP; WAIT_FRAME; JMP/JZ/JNZ label_or_u8;
STATUS rd; HALT. .WORD u32 emits a raw instruction for explicit diagnostics.
The CLI pads the image with F0000000 HALT to --words (default256, maximum256).
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys

HALT = 0xF0000000


class AssemblyError(ValueError):
    """An assembly error with a source line number."""


@dataclass(frozen=True)
class Instruction:
    line: int
    mnemonic: str
    operands: tuple[str, ...]


ALIASES = {
    "CLEAR_SCREEN": "CLEAR", "SET_PALETTE": "PALETTE",
    "WRITE_TILEMAP": "TILE", "SET_SCROLL": "SCROLL",
    "UPDATE_BIRD_Y": "BIRD_Y", "DRAW_TRI_V1": "TRI1",
    "DRAW_TRI_V2": "TRI2", "DRAW_TRI_V3": "TRI3",
    "SET_SPRITE_POS": "SPR_POS", "SET_SPRITE_ATTR": "SPR_ATTR",
    "SET_SPRITE_STYLE": "SPR_STYLE", "BUFFER_SWAP": "PRESENT",
    "SET_PALETTER": "PALETTER", "WRITE_TILEMAPR": "TILER",
    "SET_SCROLLR": "SCROLLR", "DRAW_TRI_V1R": "TRI1R",
    "DRAW_TRI_V2R": "TRI2R", "DRAW_TRI_V3R": "TRI3R",
    "SET_SPRITE_POSR": "SPR_POSR", "SET_SPRITE_ATTRR": "SPR_ATTRR",
    "SET_SPRITE_STYLER": "SPR_STYLER",
}
LABEL = re.compile(r"([A-Za-z_][A-Za-z0-9_]*):")
INTEGER = re.compile(r"[+-]?(?:0[xX][0-9a-fA-F]+|[0-9]+)\Z")
REGISTER = re.compile(r"r([0-9]+)\Z", re.IGNORECASE)


def _fail(instruction: Instruction, message: str) -> None:
    raise AssemblyError(f"line {instruction.line}: {message}")


def _arity(instruction: Instruction, expected: int) -> None:
    if len(instruction.operands) != expected:
        _fail(instruction, f"{instruction.mnemonic} expects {expected} operands, "
              f"got {len(instruction.operands)}")


def _integer(instruction: Instruction, token: str, low: int, high: int) -> int:
    if not INTEGER.fullmatch(token):
        _fail(instruction, f"expected an integer, got {token!r}")
    magnitude = token.lstrip("+-")
    value = int(token, 16 if magnitude.lower().startswith("0x") else 10)
    if not low <= value <= high:
        _fail(instruction, f"integer {token} outside range {low}..{high}")
    return value


def _register(instruction: Instruction, token: str) -> int:
    match = REGISTER.fullmatch(token)
    if match is None or not 0 <= int(match.group(1)) <= 15:
        _fail(instruction, f"invalid register {token!r}; use r0..r15")
    return int(match.group(1))


def _parse(source: str) -> tuple[list[Instruction], dict[str, int]]:
    instructions: list[Instruction] = []
    labels: dict[str, int] = {}
    address = 0
    for line_number, raw in enumerate(source.splitlines(), 1):
        body = re.split(r";|#|//", raw, maxsplit=1)[0].strip()
        while match := LABEL.match(body):
            label = match.group(1).upper()
            if label in labels:
                raise AssemblyError(f"line {line_number}: duplicate label {match.group(1)!r}")
            labels[label] = address
            body = body[match.end():].strip()
        if not body:
            continue
        if re.search(r",\s*,|,\s*$", body):
            raise AssemblyError(f"line {line_number}: missing operand after comma")
        tokens = re.split(r"[\s,]+", body)
        mnemonic = ALIASES.get(tokens[0].upper(), tokens[0].upper())
        instruction = Instruction(line_number, mnemonic, tuple(tokens[1:]))
        instructions.append(instruction)
        address += 6 if mnemonic in ("RECT", "RECTR") else 1
        if address > 256:
            _fail(instruction, "program exceeds the 256-word instruction memory")
    return instructions, labels


def _encode(instruction: Instruction, labels: dict[str, int]) -> list[int]:
    mnemonic, operands = instruction.mnemonic, instruction.operands
    def ints(*maxima: int) -> list[int]:
        _arity(instruction, len(maxima))
        return [_integer(instruction, token, 0, maximum)
                for token, maximum in zip(operands, maxima)]
    def regs(count: int) -> list[int]:
        _arity(instruction, count)
        return [_register(instruction, token) for token in operands]
    def graphics(subop: int, ra: int, rb: int = 0, rc: int = 0, sprite: int = 0) -> int:
        return 0x40000000 | subop << 24 | ra << 20 | rb << 16 | rc << 12 | sprite << 7

    if mnemonic in ("CLEAR", "PRESENT", "HALT", "NOP", "WAIT_FRAME"):
        _arity(instruction, 0)
        return [{"CLEAR": 0x0F000000, "PRESENT": 0xD1000000,
                 "HALT": HALT, "NOP": 0xE0000000, "WAIT_FRAME": 0xE1000000}[mnemonic]]
    if mnemonic == "MOVI":
        _arity(instruction, 2)
        rd = _register(instruction, operands[0])
        value = _integer(instruction, operands[1], 0, 0xFFFF)
        return [0x20000000 | rd << 20 | value]
    if mnemonic == "MOV":
        rd, ra = regs(2)
        return [0x21000000 | rd << 20 | ra << 16]
    if mnemonic in ("ADD", "SUB", "AND", "OR", "XOR", "SHL", "SHR"):
        rd, ra, rb = regs(3)
        subop = {"ADD": 2, "SUB": 3, "AND": 4, "OR": 5,
                 "XOR": 6, "SHL": 7, "SHR": 8}[mnemonic]
        return [0x20000000 | subop << 24 | rd << 20 | ra << 16 | rb << 12]
    if mnemonic == "CMP":
        ra, rb = regs(2)
        return [0x29000000 | ra << 16 | rb << 12]
    if mnemonic == "ADDI":
        _arity(instruction, 3)
        rd, ra = [_register(instruction, token) for token in operands[:2]]
        value = _integer(instruction, operands[2], -32768, 32767)
        return [0x2A000000 | rd << 20 | ra << 16 | (value & 0xFFFF)]
    if mnemonic in ("JMP", "JZ", "JNZ"):
        _arity(instruction, 1)
        target_name = operands[0].upper()
        if target_name in labels:
            target = labels[target_name]
            if not 0 <= target <= 255:
                _fail(instruction, f"label {operands[0]!r} is outside address range 0..255")
        elif INTEGER.fullmatch(operands[0]):
            target = _integer(instruction, operands[0], 0, 255)
        else:
            _fail(instruction, f"undefined label {operands[0]!r}")
        subop = {"JMP": 2, "JZ": 3, "JNZ": 4}[mnemonic]
        return [0xE0000000 | subop << 24 | target]
    if mnemonic == "STATUS":
        rd, = regs(1)
        return [0xE5000000 | rd << 20]
    if mnemonic == ".WORD":
        value, = ints(0xFFFFFFFF)
        return [value]
    if mnemonic == "PALETTE":
        address, color = ints(255, 65535)
        return [0x10000000 | address << 16 | color]
    if mnemonic == "TILE":
        x, y, tile = ints(39, 29, 255)
        return [0x30000000 | x << 16 | y << 8 | tile]
    if mnemonic == "SCROLL":
        x, y = ints(511, 255)
        return [0x50000000 | x << 8 | y]
    if mnemonic == "BIRD_Y":
        y, = ints(255)
        return [0x60000000 | y]
    if mnemonic in ("TRI1", "TRI2"):
        x, y = ints(511, 255)
        return [(0x70000000 if mnemonic == "TRI1" else 0x80000000) | x << 8 | y]
    if mnemonic == "TRI3":
        x, y, color = ints(511, 255, 255)
        return [0x90000000 | color << 20 | x << 8 | y]
    if mnemonic == "SPR_POS":
        sprite, x, y = ints(31, 511, 255)
        return [0xA0000000 | sprite << 23 | x << 14 | y << 6]
    if mnemonic == "SPR_ATTR":
        sprite, tile, enable, flip_h, flip_v = ints(31, 255, 1, 1, 1)
        return [0xB0000000 | sprite << 23 | tile << 15 | enable << 14 | flip_h << 13 | flip_v << 12]
    if mnemonic == "SPR_STYLE":
        sprite, priority, enable, bank = ints(31, 3, 1, 15)
        return [0xC0000000 | sprite << 23 | priority << 21 | enable << 20 | bank << 16]
    if mnemonic == "BUFFER_CONFIG":
        enable, = ints(1)
        return [0xD0000000 | enable]
    if mnemonic == "RECT":
        x0, y0, x1, y1, color = ints(511, 255, 511, 255, 255)
        if x1 <= x0 or y1 <= y0:
            _fail(instruction, "RECT requires x0<x1 and y0<y1 (inclusive corners with positive area)")
        corners = (("TRI1", x0, y0), ("TRI2", x1, y0), ("TRI3", x1, y1, color),
                   ("TRI1", x0, y0), ("TRI2", x1, y1), ("TRI3", x0, y1, color))
        return [word for name, *values in corners
                for word in _encode(Instruction(instruction.line, name, tuple(map(str, values))), labels)]
    if mnemonic == "RECTR":
        x0, y0, x1, y1, color = regs(5)
        return [graphics(3, x0, y0), graphics(4, x1, y0), graphics(5, x1, y1, color),
                graphics(3, x0, y0), graphics(4, x1, y1), graphics(5, x0, y1, color)]
    if mnemonic in ("EMIT", "SCROLLR", "TRI1R", "TRI2R", "TRI3R", "TILER", "PALETTER"):
        subop, count = {"EMIT": (0, 1), "SCROLLR": (1, 2), "TRI1R": (3, 2),
                         "TRI2R": (4, 2), "TRI3R": (5, 3), "TILER": (6, 3),
                         "PALETTER": (7, 2)}[mnemonic]
        values = regs(count)
        return [graphics(subop, *values)]
    if mnemonic in ("SPR_POSR", "SPR_ATTRR", "SPR_STYLER"):
        _arity(instruction, 3)
        sprite = _integer(instruction, operands[0], 0, 31)
        ra, rb = [_register(instruction, token) for token in operands[1:]]
        subop = {"SPR_POSR": 2, "SPR_ATTRR": 8, "SPR_STYLER": 9}[mnemonic]
        return [graphics(subop, ra, rb, sprite=sprite)]
    _fail(instruction, f"unknown instruction {mnemonic!r}")
    return []


def assemble(source: str, words: int | None = 256) -> list[int]:
    """Return encoded words, optionally HALT-padded; reject all overflows."""
    if words is not None and not 1 <= words <= 256:
        raise AssemblyError("image size must be between 1 and 256 words")
    instructions, labels = _parse(source)
    image = [word for instruction in instructions for word in _encode(instruction, labels)]
    if words is not None:
        if len(image) > words:
            address = 0
            for instruction in instructions:
                address += 6 if instruction.mnemonic in ("RECT", "RECTR") else 1
                if address > words:
                    _fail(instruction, f"program uses {len(image)} words, exceeds requested image size {words}")
        image.extend([HALT] * (words - len(image)))
    return image


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="Assembly source file")
    parser.add_argument("-o", "--output", type=Path, help="HEX destination (default: source with .hex suffix)")
    parser.add_argument("--words", type=int, default=256, help="HALT-padded image size, 1..256 (default:256)")
    args = parser.parse_args(argv)
    output = args.output or args.source.with_suffix(".hex")
    try:
        if output.resolve() == args.source.resolve():
            raise AssemblyError("output path must differ from source path")
        source = args.source.read_text(encoding="utf-8")
        image = assemble(source, args.words)
        used = len(assemble(source, words=None))
        output.write_text("".join(f"{word:08X}\n" for word in image), encoding="ascii")
    except (AssemblyError, OSError, UnicodeError) as error:
        print(f"{args.source}: {error}", file=sys.stderr)
        return 1
    print(f"{args.source} -> {output}: {used} instruction words, {len(image)} image words")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
