#!/usr/bin/env bash
<<<<<<< HEAD
# Compila uma copia isolada; preserva artefatos historicos versionados.
set -euo pipefail
usage() {
    echo 'Uso: bash scripts/synth_quartus.sh [--board | --active | --pbl1 | --program programs/arquivo.hex] [--words N] [--prepare-only]'
    echo 'Padrao: busca ativa, background_sprites.hex, 256 palavras.'
    echo '--board: demonstracao historica por botoes; --active: fetch_demo (9); --pbl1: validacao PBL1 (17).'
}
active=1
words=256
program=programs/background_sprites.hex
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
=======
# Compila uma copia isolada; nunca sobrescreve db/ ou output_files/ historicos.
set -euo pipefail

usage() {
    echo "Uso: bash scripts/synth_quartus.sh [--active | --pbl1] [--prepare-only]"
    echo "Sem argumento: botoes; --active: programa padrao; --pbl1: demonstracao PBL1 de 17 palavras."
    echo "--prepare-only: copiar projeto e parametros, sem executar Quartus."
}

active=0
pbl1=0
prepare_only=0
mode_selected=0
for argument in "$@"; do
    case "$argument" in
        --active|--pbl1)
            if (( mode_selected )); then usage >&2; exit 2; fi
            mode_selected=1
            active=1
            if [[ "$argument" == --pbl1 ]]; then pbl1=1; fi
            ;;
        --prepare-only) prepare_only=1 ;;
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
<<<<<<< HEAD
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
=======

if (( !prepare_only )) && ! command -v quartus_sh >/dev/null 2>&1; then
    echo "Quartus nao encontrado. Instale Quartus Prime com suporte Cyclone V e coloque quartus_sh no PATH." >&2
    echo "Nenhum .sof ou resultado de timing foi produzido." >&2
    exit 127
fi

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
mkdir -p "$repo_dir/.build/quartus"
run_dir=$(mktemp -d "$repo_dir/.build/quartus/run.XXXXXX")
shopt -s nullglob
sources=("$repo_dir"/*.v "$repo_dir"/*.hex "$repo_dir"/*.mif)
cp -- "${sources[@]}" "$repo_dir/gpu.qpf" "$repo_dir/gpu.qsf" "$repo_dir/gpu.sdc" "$run_dir/"
cp -a -- "$repo_dir/programs" "$run_dir/programs"
<<<<<<< HEAD
# Ultimas atribuicoes substituem os parametros do projeto na copia.
printf '\nset_parameter -name USE_ACTIVE_FETCH %d\nset_parameter -name PROGRAM_WORDS %d\nset_parameter -name PROGRAM_FILE {"%s"}\n' \
    "$active" "$words" "$program" >> "$run_dir/gpu.qsf"
printf 'Projeto isolado: %s\n' "$run_dir"
if (( prepare_only )); then
    echo 'Copia preparada; nenhum .sof ou relatorio de timing novo foi gerado.'
=======

# A selecao altera apenas a copia do QSF nesta execucao.
printf '\nset_parameter -name USE_ACTIVE_FETCH %d\n' "$active" >> "$run_dir/gpu.qsf"
if (( pbl1 )); then
    cat >> "$run_dir/gpu.qsf" <<'QSF'
set_parameter -name PROGRAM_WORDS 17
set_parameter -name PROGRAM_FILE {"programs/pbl1_validation.hex"}
QSF
fi
printf 'Projeto isolado: %s\n' "$run_dir"
if (( prepare_only )); then
    printf 'Copia preparada. Quartus nao foi executado; nenhum .sof ou relatorio de timing novo foi gerado.\n'
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
    exit 0
fi
cd "$run_dir"
quartus_sh --flow compile gpu 2>&1 | tee compile.log
printf 'Compilacao concluida. Confira recursos, clocks, slack e caminhos nao restringidos em %s/output_files.\n' "$run_dir"
<<<<<<< HEAD
echo 'A conclusao do comando nao substitui a revisao de timing nem a demonstracao na placa.'
=======
printf 'A conclusao do comando nao substitui a revisao de timing nem a demonstracao na placa.\n'
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
