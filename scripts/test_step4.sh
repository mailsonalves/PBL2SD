#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'HELP'
Uso: bash scripts/test_step4.sh [--cpu-only | --gallery-only]

Sem argumento: 11 casos Python, reproducibilidade Assembly/HEX/assets,
8 bancadas novas, 4 bancadas CPU e inicialização GPU em Icarus,
e as 17 regressões da etapa 3.
--cpu-only: verificações Python/HEX/assets, RF/ULA/quadros/core, entradas
            e GPU programável (6 novas bancadas); CPU e inicialização GPU em Icarus.
--gallery-only: verificações Python/HEX/assets e as 2 bancadas da galeria
                (comandos e vídeo com clocks VGA reais).

Requer Python 3, Verilator, Make e compilador C++.
Icarus Verilog (iverilog/vvp) também é necessário, exceto em --gallery-only.
Ative/instale as ferramentas antes de executar. Logs: .build/step4/ por padrão;
PBL_BUILD_DIR permite outra pasta. Capturas VGA: .build/showcase/painel0..7.ppm.
HELP
}

mode=all
case "${1:-}" in
    "") ;;
    --cpu-only) mode=cpu ;;
    --gallery-only) mode=gallery ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
if (( $# > 1 )); then usage >&2; exit 2; fi

for executable in python3 verilator make g++; do
    if ! command -v "$executable" >/dev/null 2>&1; then
        echo "$executable nao encontrado. Instale/ative as ferramentas." >&2
        exit 127
    fi
done
if [[ "$mode" != gallery ]]; then
    for executable in iverilog vvp; do
        if ! command -v "$executable" >/dev/null 2>&1; then
            echo "$executable nao encontrado. Instale/ative Icarus Verilog." >&2
            exit 127
        fi
    done
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
build_dir="${PBL_BUILD_DIR:-$repo_dir/.build/step4}"
mkdir -p "$build_dir" .build/showcase

# --check preserva os arquivos versionados e rejeita HEX/assets desatualizados.
python3 tests/test_assembler.py 2>&1 | tee "$build_dir/assembler-tests.log"
python3 scripts/assemble.py programs/core_validation.asm --check 2>&1 |
    tee "$build_dir/core-validation-check.log"
python3 scripts/assemble.py programs/showcase.asm --check 2>&1 |
    tee "$build_dir/showcase-check.log"
python3 scripts/generate_showcase_assets.py --check 2>&1 |
    tee "$build_dir/assets-check.log"

run_verilator() {
    local test_name="$1"
    shift
    echo "Teste Verilator: $test_name"
    mkdir -p "$build_dir/$test_name"
    verilator --binary --timing -j 2 -Wno-fatal \
        --top-module "$test_name" --Mdir "$build_dir/$test_name" \
        "$@" > "$build_dir/$test_name/build.log" 2>&1 || {
            local result=$?
            cat "$build_dir/$test_name/build.log" >&2
            return "$result"
        }
    "$build_dir/$test_name/V$test_name" 2>&1 | tee "$build_dir/$test_name/run.log"
}

run_icarus() {
    local test_name="$1"
    local top_module="$2"
    shift 2
    echo "Teste Icarus (quatro estados): $test_name"
    mkdir -p "$build_dir/four-state"
    iverilog -g2012 -s "$top_module" -o "$build_dir/four-state/$test_name.vvp" \
        "$@" > "$build_dir/four-state/$test_name-build.log" 2>&1 || {
            local result=$?
            cat "$build_dir/four-state/$test_name-build.log" >&2
            return "$result"
        }
    vvp "$build_dir/four-state/$test_name.vvp" 2>&1 |
        tee "$build_dir/four-state/$test_name-run.log"
}

core_sources=(gpu_program_core.v gpu_register_file.v gpu_alu.v \
              gpu_status_register.v gpu_frame_control.v instruction_memory.v)
if [[ "$mode" != gallery ]]; then
    run_verilator tb_gpu_register_file gpu_register_file.v tests/tb_gpu_register_file.sv
    run_verilator tb_gpu_alu gpu_alu.v tests/tb_gpu_alu.sv
    run_verilator tb_gpu_frame_control gpu_frame_control.v tests/tb_gpu_frame_control.sv
    run_verilator tb_gpu_program_core "${core_sources[@]}" tests/tb_gpu_program_core.sv
    run_verilator tb_showcase_inputs showcase_inputs.v tests/tb_showcase_inputs.sv
    run_verilator tb_programmable_gpu ./*.v tests/tb_programmable_gpu.sv

    # Verilator utiliza dois estados; Icarus verifica também sinais indefinidos.
    run_icarus tb_gpu_register_file tb_gpu_register_file gpu_register_file.v tests/tb_gpu_register_file.sv
    run_icarus tb_gpu_alu tb_gpu_alu gpu_alu.v tests/tb_gpu_alu.sv
    run_icarus tb_gpu_frame_control tb_gpu_frame_control gpu_frame_control.v tests/tb_gpu_frame_control.sv
    run_icarus tb_gpu_program_core tb_gpu_program_core "${core_sources[@]}" tests/tb_gpu_program_core.sv
    # Repete a bancada de X/reset com CPU e assets da galeria selecionados.
    # A variante legada continua na suíte da etapa 3.
    run_icarus tb_initialization_programmable tb_initialization \
        -P tb_initialization.USE_PROGRAMMABLE_CORE=1 -P tb_initialization.SHOWCASE=1 \
        ./*.v tests/tb_initialization.sv
fi

if [[ "$mode" != cpu ]]; then
    run_verilator tb_showcase_commands ./*.v tests/tb_showcase_commands.sv
    run_verilator tb_showcase_video ./*.v tests/tb_showcase_video.sv
fi

if [[ "$mode" == all ]]; then
    # Etapa 3 inclui regressões das etapas 2 e 1 e inicialização em Icarus.
    echo 'Executando as 17 regressões das etapas anteriores...'
    PBL_BUILD_DIR="$build_dir/regression" bash "$repo_dir/scripts/test_step3.sh" 2>&1 |
        tee "$build_dir/regression.log"
    echo 'PASS etapa 4: 25 bancadas SV distintas + 11 casos Python; CPU e inicialização GPU também em Icarus.'
elif [[ "$mode" == cpu ]]; then
    echo 'PASS etapa 4 CPU: 6 novas bancadas SV + 11 casos Python; CPU e inicialização GPU também em Icarus.'
else
    echo 'PASS etapa 4 galeria: 2 bancadas SV + 11 casos Python; oito capturas VGA disponíveis.'
fi
