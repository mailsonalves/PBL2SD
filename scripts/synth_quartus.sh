#!/usr/bin/env bash
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
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

if (( !prepare_only )) && ! command -v quartus_sh >/dev/null 2>&1; then
    echo "Quartus nao encontrado. Instale Quartus Prime com suporte Cyclone V e coloque quartus_sh no PATH." >&2
    echo "Nenhum .sof ou resultado de timing foi produzido." >&2
    exit 127
fi

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$repo_dir/.build/quartus"
run_dir=$(mktemp -d "$repo_dir/.build/quartus/run.XXXXXX")
shopt -s nullglob
sources=("$repo_dir"/*.v "$repo_dir"/*.hex "$repo_dir"/*.mif)
cp -- "${sources[@]}" "$repo_dir/gpu.qpf" "$repo_dir/gpu.qsf" "$repo_dir/gpu.sdc" "$run_dir/"
cp -a -- "$repo_dir/programs" "$run_dir/programs"

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
    exit 0
fi
cd "$run_dir"
quartus_sh --flow compile gpu 2>&1 | tee compile.log
printf 'Compilacao concluida. Confira recursos, clocks, slack e caminhos nao restringidos em %s/output_files.\n' "$run_dir"
printf 'A conclusao do comando nao substitui a revisao de timing nem a demonstracao na placa.\n'
