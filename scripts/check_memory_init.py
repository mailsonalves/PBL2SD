#!/usr/bin/env python3
"""Compare HEX words with the initial contents retained in a Yosys netlist."""
import argparse
import json
from pathlib import Path
import sys


def check(run_dir):
    repo = Path(__file__).resolve().parent.parent
    mode = dict(line.split("=", 1) for line in
                (run_dir / "mode.txt").read_text().splitlines() if "=" in line)
    gallery = mode["SHOWCASE"] == "1"
    prefix = "assets/showcase_" if gallery else ""
    expected = {
        ("pattern_vram", "ram"): (prefix + "tiles.hex", 8),
        ("sprite_engine", "pattern_rom"): (prefix + "tiles.hex", 8),
        ("tilemap_ram", "map_ram"): (
            "assets/showcase_tilemap.hex" if gallery else "tilemap_data.hex", 8),
        ("color_palette", "clut_ram"): (prefix + "palette.hex", 24),
    }
    if mode["USE_PROGRAMMABLE_CORE"] == "1" or mode["USE_ACTIVE_FETCH"] == "1":
        expected[("instruction_memory", "memory")] = (mode["PROGRAM_FILE"], 32)

    modules = json.loads((run_dir / "structure.json").read_text())["modules"]
    checked = set()
    for name, module in modules.items():
        original = module.get("attributes", {}).get("hdlname", name)
        for cell_name, cell in module.get("cells", {}).items():
            key = (original, cell_name)
            if key not in expected or not cell["type"].startswith("$mem"):
                continue
            filename, width = expected[key]
            words = [int(word, 16) for word in (repo / filename).read_text().split()]
            params = cell["parameters"]
            size = int(params["SIZE"], 2)
            init = params.get("INIT", "")
            if int(params["WIDTH"], 2) != width or size != len(words):
                raise ValueError(f"{original}.{cell_name}: dimensoes diferentes de {filename}")
            if len(init) != width * size or set(init) - {"0", "1"}:
                raise ValueError(f"{original}.{cell_name}: inicializacao ausente/indefinida")
            for address, value in enumerate(words):
                start = len(init) - (address + 1) * width
                actual = int(init[start:start + width], 2)
                if actual != value:
                    raise ValueError(f"{original}.{cell_name}[{address}]: "
                                     f"{actual:X}, esperado {value:X} de {filename}")
            checked.add(key)
            print(f"PASS INIT: {original}.{cell_name}, {size} palavras de {filename}")
    missing = expected.keys() - checked
    if missing:
        raise ValueError(f"Memorias nao encontradas no netlist: {sorted(missing)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path, help="pasta .build/synth/run.XXXXXX")
    args = parser.parse_args()
    try:
        check(args.run_dir)
    except (ValueError, KeyError, OSError) as error:
        print(f"FAIL INIT: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
