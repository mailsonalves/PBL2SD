#!/usr/bin/env python3
"""Assemble the PBL2 word-addressed ISA using only the Python standard library.

Examples:
    python3 scripts/assemble.py programs/showcase.asm
    python3 scripts/assemble.py programs/showcase.asm --check
    python3 scripts/assemble.py input.asm -o output.hex --symbols symbols.json

``.word`` deliberately accepts any 32-bit word, including invalid instructions,
so programs can exercise the processor's error handling.
"""

import argparse
import json
from pathlib import Path
import re
import sys


MAX_WORDS = 4096
_LABEL = re.compile(r"^([A-Za-z_][A-Za-z_0-9]*)\s*:")
_NUMBER = re.compile(r"^[+-]?(?:0[xX][0-9a-fA-F]+|0[bB][01]+|[0-9]+)$")
_REGISTER = re.compile(r"^[rR]([0-9]+)$")


class AssemblyError(ValueError):
    """A source error with an optional one-based source line."""

    def __init__(self, message, line=None):
        self.line = line
        super().__init__(f"line {line}: {message}" if line else message)


def _integer(token, line):
    if not _NUMBER.fullmatch(token):
        raise AssemblyError(f"expected integer, got '{token}'", line)
    sign = -1 if token.startswith("-") else 1
    unsigned = token.lstrip("+-")
    base = 16 if unsigned.lower().startswith("0x") else 2 if unsigned.lower().startswith("0b") else 10
    try:
        return sign * int(unsigned, base)
    except ValueError:
        raise AssemblyError(f"invalid or excessively long integer '{token[:40]}'", line) from None


def _range(token, minimum, maximum, description, line):
    value = _integer(token, line)
    if not minimum <= value <= maximum:
        raise AssemblyError(f"{description} must be in {minimum}..{maximum}, got {value}", line)
    return value


def _word(token, line):
    return _range(token, -(1 << 31), (1 << 32) - 1, "32-bit value", line) & 0xFFFFFFFF


def _reg(token, line):
    match = _REGISTER.fullmatch(token)
    if not match or int(match.group(1)) > 15:
        raise AssemblyError(f"expected register R0..R15, got '{token}'", line)
    return int(match.group(1))


def _arity(mnemonic, operands, count, line):
    if len(operands) != count:
        raise AssemblyError(f"{mnemonic} expects {count} operand(s), got {len(operands)}", line)


def _encode(mnemonic, args, labels, program_words, line):
    def count(n):
        _arity(mnemonic, args, n, line)

    def number(i, lo, hi, name):
        return _range(args[i], lo, hi, name, line)

    def register(i):
        return _reg(args[i], line)

    no_args = {"CLEAR": 0x0F000000, "PRESENT": 0xD1000000,
               "WAIT_FRAME": 0xE0000000, "CLRE": 0x2D000000, "HALT": 0xF0000000}
    if mnemonic in no_args:
        count(0)
        return [no_args[mnemonic]]
    if mnemonic == ".WORD":
        count(1)
        return [_word(args[0], line)]
    if mnemonic in ("LI", "LDI"):
        count(2)
        rd = register(0)
        value = _word(args[1], line) if mnemonic == "LI" else number(1, 0, 0xFFFFF, "LDI immediate")
        if value <= 0xFFFFF:
            return [0x20000000 | rd << 20 | value]
        return [0x2E000000 | rd << 20 | (value >> 16),
                0x2F000000 | rd << 20 | rd << 16 | (value & 0xFFFF)]
    alu_ops = {"ADD": 1, "SUB": 2, "AND": 3, "OR": 4, "XOR": 5, "SHL": 6, "SHR": 7}
    if mnemonic in alu_ops:
        count(3)
        return [0x20000000 | alu_ops[mnemonic] << 24 | register(0) << 20 |
                register(1) << 16 | register(2) << 12]
    if mnemonic == "CMP":
        count(2)
        return [0x28000000 | register(0) << 16 | register(1) << 12]
    if mnemonic == "MOV":
        count(2)
        return [0x29000000 | register(0) << 20 | register(1) << 16]
    if mnemonic in ("ADDI", "ORI"):
        count(3)
        value = number(2, -32768, 32767, "ADDI immediate") if mnemonic == "ADDI" else number(2, 0, 65535, "ORI immediate")
        return [(0x2A000000 if mnemonic == "ADDI" else 0x2F000000) |
                register(0) << 20 | register(1) << 16 | (value & 0xFFFF)]
    if mnemonic == "LUI":
        count(2)
        return [0x2E000000 | register(0) << 20 | number(1, 0, 65535, "LUI immediate")]
    if mnemonic == "IN":
        count(2)
        return [0x2B000000 | register(0) << 20 | number(1, 0, 2, "input port") << 16]
    if mnemonic == "STATUS":
        count(1)
        return [0x2C000000 | register(0) << 20]
    if mnemonic == "CMD":
        count(1)
        return [0x40000000 | register(0) << 24]
    branches = {"JMP": 1, "BEQ": 2, "BNE": 3, "BLT": 4, "BGE": 5}
    if mnemonic in branches:
        count(1)
        target = labels[args[0]] if args[0] in labels else _integer(args[0], line) if _NUMBER.fullmatch(args[0]) else None
        if target is None:
            raise AssemblyError(f"undefined label '{args[0]}'", line)
        if not 0 <= target < program_words:
            raise AssemblyError(f"jump target {target} outside program (0..{program_words - 1})", line)
        return [0xE0000000 | branches[mnemonic] << 24 | target]
    if mnemonic == "OUT":
        count(2)
        return [0xE6000000 | number(0, 0, 0, "output port") << 16 | register(1) << 20]
    if mnemonic == "PALETTE":
        count(2)
        return [0x10000000 | number(0, 0, 255, "palette index") << 16 |
                number(1, 0, 65535, "RGB565 color")]
    if mnemonic == "TILE":
        count(3)
        return [0x30000000 | number(0, 0, 39, "tile X") << 16 |
                number(1, 0, 29, "tile Y") << 8 | number(2, 0, 255, "tile image")]
    if mnemonic in ("SCROLL", "V0", "V1"):
        count(2)
        base = {"SCROLL": 0x50000000, "V0": 0x70000000, "V1": 0x80000000}[mnemonic]
        return [base | number(0, 0, 511, "X") << 8 | number(1, 0, 255, "Y")]
    if mnemonic == "TRI":
        count(3)
        return [0x90000000 | number(2, 0, 255, "polygon color") << 20 |
                number(0, 0, 511, "X") << 8 | number(1, 0, 255, "Y")]
    if mnemonic == "SPRPOS":
        count(3)
        return [0xA0000000 | number(0, 0, 31, "sprite ID") << 23 |
                number(1, 0, 511, "sprite X") << 14 | number(2, 0, 255, "sprite Y") << 6]
    if mnemonic == "SPRATTR":
        count(5)
        return [0xB0000000 | number(0, 0, 31, "sprite ID") << 23 |
                number(1, 0, 255, "sprite image") << 15 | number(2, 0, 1, "enable") << 14 |
                number(3, 0, 1, "horizontal flip") << 13 | number(4, 0, 1, "vertical flip") << 12]
    if mnemonic == "SPRSTYLE":
        count(4)
        return [0xC0000000 | number(0, 0, 31, "sprite ID") << 23 |
                number(1, 0, 3, "sprite priority") << 21 | number(2, 0, 1, "palette enable") << 20 |
                number(3, 0, 15, "palette bank") << 16]
    if mnemonic == "BUFFER":
        count(1)
        return [0xD0000000 | number(0, 0, 1, "double-buffer mode")]
    raise AssemblyError(f"unknown instruction '{mnemonic}'", line)


def assemble(source):
    """Return (32-bit words, label-to-word-index dictionary) for source text."""
    statements = []
    labels = {}
    pc = 0
    for line_number, raw in enumerate(source.splitlines(), 1):
        line = re.split(r"[;#]", raw, maxsplit=1)[0].strip()
        while True:
            match = _LABEL.match(line)
            if not match:
                break
            label = match.group(1)
            if label in labels:
                raise AssemblyError(f"duplicate label '{label}'", line_number)
            labels[label] = pc
            line = line[match.end():].strip()
        if not line:
            continue
        if ":" in line:
            raise AssemblyError("invalid label syntax", line_number)
        tokens = line.split(None, 1)
        mnemonic = tokens[0].upper()
        operand_text = tokens[1].strip() if len(tokens) > 1 else ""
        if operand_text.startswith(",") or operand_text.endswith(",") or re.search(r",\s*,", operand_text):
            raise AssemblyError("missing operand next to comma", line_number)
        args = re.split(r"[\s,]+", operand_text) if operand_text else []
        length = 1
        if mnemonic == "LI":
            _arity(mnemonic, args, 2, line_number)
            _reg(args[0], line_number)
            length = 1 if _word(args[1], line_number) <= 0xFFFFF else 2
        statements.append((line_number, mnemonic, args))
        pc += length
        if pc > MAX_WORDS:
            raise AssemblyError(f"program exceeds {MAX_WORDS} words", line_number)
    if not statements:
        raise AssemblyError("program contains no instructions")
    words = []
    for line, mnemonic, args in statements:
        words.extend(_encode(mnemonic, args, labels, pc, line))
    return words, labels


def _read_hex(path):
    words = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        token = raw.strip()
        if not token:
            continue
        if not re.fullmatch(r"[0-9A-Fa-f]{8}", token):
            raise AssemblyError(f"{path}:{number}: expected one eight-digit hexadecimal word")
        words.append(int(token, 16))
    return words


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", type=Path, help="Assembly source")
    parser.add_argument("-o", "--output", type=Path, help="HEX output (default: source with .hex suffix)")
    parser.add_argument("--check", action="store_true", help="compare existing HEX (and optional symbols JSON); write nothing")
    parser.add_argument("--symbols", type=Path, help="write label addresses to JSON, or compare JSON with --check")
    args = parser.parse_args(argv)
    output = args.output or args.input.with_suffix(".hex")
    try:
        if args.input.resolve() == output.resolve():
            raise AssemblyError("input and output must be different files")
        if args.symbols and args.symbols.resolve() in (args.input.resolve(), output.resolve()):
            raise AssemblyError("symbols path must differ from input and output")
        words, labels = assemble(args.input.read_text(encoding="utf-8"))
        if args.check:
            actual = _read_hex(output)
            if actual != words:
                first = next((i for i, pair in enumerate(zip(actual, words)) if pair[0] != pair[1]), min(len(actual), len(words)))
                raise AssemblyError(f"{output} is stale: first difference at word {first}; regenerate without --check")
            if args.symbols and json.loads(args.symbols.read_text(encoding="utf-8")) != labels:
                raise AssemblyError(f"{args.symbols} is stale: labels differ")
        else:
            output.write_text("".join(f"{word:08X}\n" for word in words), encoding="utf-8")
            if args.symbols:
                args.symbols.write_text(json.dumps(labels, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (AssemblyError, OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"{args.input}: {error}", file=sys.stderr)
        return 1
    print(f"{'PASS: checked' if args.check else 'Assembled'} {len(words)} words: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
