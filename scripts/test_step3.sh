#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
build_dir="${PBL_BUILD_DIR:-$repo_dir/.build/step3}"
mkdir -p "$build_dir"
four_state_only=0
case "${1:-}" in
    "") ;;
    --four-state-only) four_state_only=1 ;;
    -h|--help) echo 'Uso: bash scripts/test_step3.sh [--four-state-only]'; exit 0 ;;
    *) echo 'Argumento invalido.' >&2; exit 2 ;;
esac
if (( $# > 1 )); then echo 'Argumentos extras.' >&2; exit 2; fi

for executable in iverilog vvp; do
    if ! command -v "$executable" >/dev/null 2>&1; then
        echo "$executable nao encontrado. Instale/ative Icarus Verilog." >&2
        exit 127
    fi
done

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

if (( !four_state_only )); then
    if ! command -v verilator >/dev/null 2>&1; then
        echo 'Verilator nao encontrado. Instale/ative as ferramentas.' >&2
        exit 127
    fi
    run_test tb_cmd_decoder cmd_decoder.v tests/tb_cmd_decoder.sv
    run_test tb_background bg_engine.v tilemap_ram.v tests/tb_background.sv
    run_test tb_memories_compositor pattern_vram.v color_palette.v compositor.v tests/tb_memories_compositor.sv
    run_test tb_raster_alu raster_alu.v tests/tb_raster_alu.sv
    run_test tb_polygon_rasterizer raster_alu.v polygon_rasterizer.v tests/tb_polygon_rasterizer.sv
    run_test tb_polygon_buffer polygon_buffer.v tests/tb_polygon_buffer.sv
    run_test tb_sprite_layers sprite_engine.v tests/tb_sprite_layers.sv
    run_test tb_board_handshake board_input_controller.v tests/tb_board_handshake.sv
    run_test tb_vga_sync vga_sync.v tests/tb_vga_sync.sv
    run_test tb_pbl1_integration ./*.v tests/tb_pbl1_integration.sv
    bash "$repo_dir/scripts/test_step2.sh"
fi

# Verilator usa dois estados: Icarus verifica propagacao de X no reset/boot.
iverilog -g2012 -s tb_initialization -o "$build_dir/tb_initialization.vvp" \
    ./*.v tests/tb_initialization.sv > "$build_dir/tb_initialization-build.log" 2>&1 || {
        result=$?
        cat "$build_dir/tb_initialization-build.log" >&2
        exit "$result"
    }
vvp "$build_dir/tb_initialization.vvp"
