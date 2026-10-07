#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
build_dir="${PBL_BUILD_DIR:-$repo_dir/.build/step2}"
mkdir -p "$build_dir"
if ! command -v verilator >/dev/null 2>&1; then
    echo 'Verilator nao encontrado. Ative as ferramentas antes de executar os testes.' >&2
    exit 127
fi

run_test() {
    local test_name="$1"
    shift
    mkdir -p "$build_dir/$test_name"
    verilator --binary --timing -j 2 -Wno-fatal \
        --top-module "$test_name" --Mdir "$build_dir/$test_name" \
        "$@" > "$build_dir/$test_name/build.log" 2>&1 || {
            local result=$?
            cat "$build_dir/$test_name/build.log" >&2
            return "$result"
        }
    "$build_dir/$test_name/V$test_name"
}

run_test tb_sprite_commands cmd_decoder.v sprite_engine.v tests/tb_sprite_commands.sv
run_test tb_sprites_active_fetch ./*.v tests/tb_sprites_active_fetch.sv

# Mantem os quatro testes da etapa anterior como regressao.
bash "$repo_dir/scripts/test_step1.sh"
