#!/usr/bin/env bash
# Compila uma copia isolada; nunca sobrescreve db/ ou output_files/ historicos.
set -euo pipefail

usage() {
    echo "Uso: bash scripts/synth_quartus.sh [--showcase | --pbl2 | --legacy | --active | --pbl1] [--prepare-only]"
    echo "Padrao/--showcase/--pbl2: galeria programavel do Problema 2."
    echo "--legacy: botoes antigos; --active: busca antiga de 9 palavras; --pbl1: demonstracao PBL1."
    echo "--prepare-only: copiar projeto e parametros, sem executar Quartus."
}

mode=showcase
prepare_only=0
mode_selected=0
for argument in "$@"; do
    case "$argument" in
        --showcase|--pbl2|--legacy|--active|--pbl1)
            if (( mode_selected )); then usage >&2; exit 2; fi
            mode_selected=1
            mode=${argument#--}
            if [[ "$mode" == pbl2 ]]; then mode=showcase; fi
            ;;
        --prepare-only) prepare_only=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 nao encontrado. Instale Python 3 para verificar o programa." >&2
    exit 127
fi

core=0
showcase=0
active=0
program_file=programs/fetch_demo.hex
case "$mode" in
    showcase)
        core=1
        showcase=1
        program_file=programs/showcase.hex
        # Nao altera o Assembly nem o .hex: exige fontes e programa coerentes.
        python3 "$repo_dir/scripts/assemble.py" "$repo_dir/programs/showcase.asm" --check
        python3 "$repo_dir/scripts/generate_showcase_assets.py" --check
        ;;
    active) active=1 ;;
    pbl1) active=1; program_file=programs/pbl1_validation.hex ;;
    legacy) ;;
esac
program_words=$(python3 - "$repo_dir/$program_file" <<'PYTHON'
import pathlib
import re
import sys

words = pathlib.Path(sys.argv[1]).read_text().split()
if not 1 <= len(words) <= 4096 or any(not re.fullmatch(r'[0-9a-fA-F]{8}', word) for word in words):
    raise SystemExit('Programa deve conter de 1 a 4096 palavras hexadecimais de 32 bits.')
print(len(words))
PYTHON
)

if (( !prepare_only )) && ! command -v quartus_sh >/dev/null 2>&1; then
    echo "Quartus nao encontrado. Instale Quartus Prime com suporte Cyclone V e coloque quartus_sh no PATH." >&2
    echo "Nenhum .sof ou resultado de timing foi produzido." >&2
    exit 127
fi

mkdir -p "$repo_dir/.build/quartus"
run_dir=$(mktemp -d "$repo_dir/.build/quartus/run.XXXXXX")
shopt -s nullglob
sources=("$repo_dir"/*.v "$repo_dir"/*.hex "$repo_dir"/*.mif)
cp -- "${sources[@]}" "$repo_dir/gpu.qpf" "$repo_dir/gpu.qsf" "$repo_dir/gpu.sdc" "$run_dir/"
cp -a -- "$repo_dir/programs" "$run_dir/programs"
if [[ -d "$repo_dir/assets" ]]; then
    cp -a -- "$repo_dir/assets" "$run_dir/assets"
elif (( showcase )); then
    echo "Diretorio assets ausente: a copia da galeria ficaria incompleta." >&2
    exit 1
fi

# A selecao altera apenas a copia do QSF nesta execucao.
cat >> "$run_dir/gpu.qsf" <<QSF

set_parameter -name USE_PROGRAMMABLE_CORE $core
set_parameter -name SHOWCASE $showcase
set_parameter -name USE_ACTIVE_FETCH $active
set_parameter -name PROGRAM_WORDS $program_words
set_parameter -name PROGRAM_FILE {"$program_file"}
QSF
cat > "$run_dir/mode.txt" <<MODE
mode=$mode
USE_PROGRAMMABLE_CORE=$core
SHOWCASE=$showcase
USE_ACTIVE_FETCH=$active
PROGRAM_WORDS=$program_words
PROGRAM_FILE=$program_file
MODE
printf 'Modo: %s (%d palavras, %s)\n' "$mode" "$program_words" "$program_file"
printf 'Projeto isolado: %s\n' "$run_dir"
if (( prepare_only )); then
    printf 'Copia preparada. Quartus nao foi executado; nenhum .sof ou relatorio de timing novo foi gerado.\n'
    exit 0
fi
cd "$run_dir"
quartus_sh --flow compile gpu 2>&1 | tee compile.log
printf 'Compilacao concluida. Confira recursos, clocks, slack e caminhos nao restringidos em %s/output_files.\n' "$run_dir"
printf 'Arquivo para o Quartus Programmer: %s/output_files/gpu.sof\n' "$run_dir"
printf 'A conclusao do comando nao substitui a revisao de timing nem a demonstracao na placa.\n'
