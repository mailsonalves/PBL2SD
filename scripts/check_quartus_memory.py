#!/usr/bin/env python3
"""Reject the memory initialization warnings found in the failed board build."""
import argparse
from pathlib import Path
import re
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("report", type=Path, help="output_files/gpu.map.rpt")
args = parser.parse_args()
try:
    lines = args.report.read_text(errors="replace").splitlines()
except OSError as error:
    parser.exit(1, f"FAIL: nao foi possivel conferir o relatorio: {error}\n")

empty = re.compile(r"Warning \(10850\).*number of words \(0\)", re.I)
undefined = re.compile(r"Warning \(127007\).*gpu\.ram\d+_"
                       r"(?:pattern_vram|sprite_engine|color_palette|tilemap_ram)_", re.I)
failures = list(dict.fromkeys(line for line in lines
                             if empty.search(line) or undefined.search(line)))
if failures:
    print("FAIL: Quartus compilou com memorias graficas vazias/indefinidas.", file=sys.stderr)
    for line in failures:
        print(line, file=sys.stderr)
    sys.exit(1)
print("PASS: relatorio Quartus sem os avisos de memoria vazia/indefinida verificados.")
