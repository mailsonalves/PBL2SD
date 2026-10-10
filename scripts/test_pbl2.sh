#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
build_dir="${PBL_BUILD_DIR:-$repo_dir/.build/pbl2}"
mkdir -p "$build_dir"
for executable in verilator iverilog vvp python3 g++ make; do
    command -v "$executable" >/dev/null || { echo "$executable nao encontrado." >&2; exit 127; }
done
python3 -m unittest discover -s tests -p 'test_assembler.py' -v
# Compara a fonte Assembly com o HEX publicado sem sobrescrever programas.
for program in background_sprites polygons_motion; do
    python3 tools/assemble.py "programs/$program.asm" -o "$build_dir/$program.hex" --words 256
    cmp "programs/$program.hex" "$build_dir/$program.hex"
done
run_test() {
    local test_name="$1"
    mkdir -p "$build_dir/$test_name"
    verilator --binary --timing -j 2 -Wno-fatal --top-module "$test_name" \
        --Mdir "$build_dir/$test_name" ./*.v "tests/$test_name.sv" \
        > "$build_dir/$test_name/build.log" 2>&1 || {
            local result=$?
            cat "$build_dir/$test_name/build.log" >&2
            return "$result"
        }
    "$build_dir/$test_name/V$test_name"
}
run_test tb_gpu_cpu_units
run_test tb_gpu_cpu_control
run_test tb_gpu_mmio
# Quatro estados tambem exercitam o datapath/controle novo, alem do boot VGA.
for test_name in tb_gpu_cpu_units tb_gpu_cpu_control tb_gpu_mmio; do
    iverilog -g2012 -s "$test_name" -o "$build_dir/$test_name.vvp" \
        ./*.v "tests/$test_name.sv" > "$build_dir/$test_name-icarus-build.log" 2>&1 || {
            result=$?
            cat "$build_dir/$test_name-icarus-build.log" >&2
            exit "$result"
        }
    vvp "$build_dir/$test_name.vvp"
done
run_test tb_pbl2_programs
run_test tb_pbl2_control
# Regressoes graficas completas e inicializacao em quatro estados.
bash "$repo_dir/scripts/test_step3.sh"
