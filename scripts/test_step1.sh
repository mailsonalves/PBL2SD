#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
build_dir="${PBL_BUILD_DIR:-$repo_dir/.build/step1}"
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

run_test tb_instruction_memory instruction_memory.v tests/tb_instruction_memory.sv
run_test tb_active_fetch_controller instruction_memory.v active_fetch_controller.v \
    gpu_alu.v gpu_register_file.v gpu_instruction_decoder.v gpu_datapath.v \
    tests/tb_active_fetch_controller.sv
run_test tb_active_fetch_integration ./*.v tests/tb_active_fetch_integration.sv
run_test tb_board_demo ./*.v tests/tb_board_demo.sv
