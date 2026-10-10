#!/usr/bin/env bash
# Compila uma copia isolada; preserva artefatos historicos versionados.
set -euo pipefail
usage() {
    echo 'Uso: bash scripts/synth_quartus.sh [--board | --active | --pbl1 | --program programs/arquivo.hex] [--words N] [--prepare-only]'
    echo 'Padrao: busca ativa, background_motion.hex continuo, 256 palavras.'
    echo '--board: demonstracao historica por botoes; --active: fetch_demo (9); --pbl1: validacao PBL1 (17).'
}
active=1
words=256
program=programs/background_motion.hex
prepare_only=0
mode_selected=0
while (( $# )); do
    case "$1" in
        --board|--active|--pbl1)
            if (( mode_selected )); then usage >&2; exit 2; fi
            mode_selected=1
            case "$1" in
                --board) active=0 ;;
                --active) program=programs/fetch_demo.hex; words=9 ;;
                --pbl1) program=programs/pbl1_validation.hex; words=17 ;;
            esac
            shift ;;
        --program)
            if (( mode_selected || $# < 2 )); then usage >&2; exit 2; fi
            mode_selected=1; program=$2; shift 2 ;;
        --words)
            if (( $# < 2 )); then usage >&2; exit 2; fi
            words=$2; shift 2 ;;
        --prepare-only) prepare_only=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# O projeto isolado copia programs/. Impede caminhos que escapem dessa copia.
if [[ ! "$words" =~ ^[0-9]{1,3}$ ]] || (( 10#$words < 1 || 10#$words > 256 )) ||
   [[ ! "$program" =~ ^programs/[A-Za-z0-9_-]+\.hex$ ]] || [[ ! -f "$repo_dir/$program" ]]; then
    echo 'Programa deve existir em programs/*.hex; --words deve estar entre 1 e 256.' >&2
    exit 2
fi
words=$((10#$words))
# A ROM deve receber exatamente as palavras solicitadas; evita boot com X.
python3 - "$repo_dir/$program" "$words" <<'PYTHON'
from pathlib import Path
import re
import sys
words = [word for line in Path(sys.argv[1]).read_text().splitlines()
         for word in line.split('//', 1)[0].split()]
if len(words) != int(sys.argv[2]) or any(not re.fullmatch(r'[0-9A-Fa-f]{8}', word) for word in words):
    sys.exit('HEX deve conter exatamente --words palavras de 32 bits (uma palavra hexadecimal por entrada).')
PYTHON
if (( !prepare_only )) && ! command -v quartus_sh >/dev/null 2>&1; then
    echo 'Quartus nao encontrado. Instale Quartus Prime com suporte Cyclone V e coloque quartus_sh no PATH.' >&2
    echo 'Nenhum .sof ou resultado de timing foi produzido.' >&2
    exit 127
fi
mkdir -p "$repo_dir/.build/quartus"
run_dir=$(mktemp -d "$repo_dir/.build/quartus/run.XXXXXX")
shopt -s nullglob
sources=("$repo_dir"/*.v "$repo_dir"/*.hex "$repo_dir"/*.mif)
cp -- "${sources[@]}" "$repo_dir/gpu.qpf" "$repo_dir/gpu.qsf" "$repo_dir/gpu.sdc" "$run_dir/"
cp -a -- "$repo_dir/programs" "$run_dir/programs"
# Caminho HEX como literal Verilog: evita aspas literais de override no QSF.
# Altera somente a copia; gpu_core recebe o parametro do wrapper de placa.
python3 - "$run_dir/gpu.qsf" "$run_dir/gpu_de1_soc_top.v" "$program" <<'PYTHON'
from pathlib import Path
import json
import re
import sys
qsf, top = map(Path, sys.argv[1:3])
text, count = re.subn(r'(?m)^(\s*parameter\s+PROGRAM_FILE\s*=\s*)"[^"\n]*"',
                      lambda match: match[1] + json.dumps(sys.argv[3]), top.read_text())
if count != 1:
    sys.exit('Esperado exatamente um parametro PROGRAM_FILE no top da copia.')
top.write_text(text)
qsf.write_text(''.join(line for line in qsf.read_text().splitlines(keepends=True)
                       if not re.match(r'^\s*set_parameter\s+-name\s+"?PROGRAM_FILE"?\s', line)))
PYTHON
# Parametros numericos continuam configurados no QSF da copia.
printf '\nset_parameter -name USE_ACTIVE_FETCH %d\nset_parameter -name PROGRAM_WORDS %d\n' \
    "$active" "$words" >> "$run_dir/gpu.qsf"
printf 'Projeto isolado: %s\n' "$run_dir"
if (( prepare_only )); then
    echo 'Copia preparada; nenhum .sof ou relatorio de timing novo foi gerado.'
    exit 0
fi
cd "$run_dir"
quartus_sh --flow compile gpu 2>&1 | tee compile.log
printf 'Compilacao concluida. Confira recursos, clocks, slack e caminhos nao restringidos em %s/output_files.\n' "$run_dir"
echo 'A conclusao do comando nao substitui a revisao de timing nem a demonstracao na placa.'
