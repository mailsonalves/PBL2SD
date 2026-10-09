#!/usr/bin/env bash
# Verifica estrutura e inferencia de RAM antes de Quartus/TimeQuest.
# Nao estima Fmax nem produz bitstream. Os resultados sao preliminares.
set -euo pipefail

usage() {
    echo "Uso: bash scripts/synth_precheck.sh [--showcase | --pbl2 | --legacy | --active | --pbl1] [--structure-only]"
    echo "Padrao/--showcase/--pbl2: galeria programavel, estrutura e mapeamento preliminar Cyclone V."
    echo "--legacy: botoes antigos; --active: busca antiga; --pbl1: demonstracao PBL1."
}
mode=showcase
mode_selected=0
structure_only=0
for argument in "$@"; do
    case "$argument" in
        --showcase|--pbl2|--legacy|--active|--pbl1)
            if (( mode_selected )); then usage >&2; exit 2; fi
            mode_selected=1
            mode=${argument#--}
            if [[ "$mode" == pbl2 ]]; then mode=showcase; fi
            ;;
        --structure-only) structure_only=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
for executable in yosys python3; do
    if ! command -v "$executable" >/dev/null 2>&1; then
        echo "$executable nao encontrado. Ative/instale as ferramentas antes do precheck." >&2
        exit 127
    fi
done

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"
core=0
showcase=0
active=0
program_file=programs/fetch_demo.hex
case "$mode" in
    showcase)
        core=1
        showcase=1
        program_file=programs/showcase.hex
        python3 scripts/assemble.py programs/showcase.asm --check
        python3 scripts/generate_showcase_assets.py --check
        ;;
    active) active=1 ;;
    pbl1) active=1; program_file=programs/pbl1_validation.hex ;;
    legacy) ;;
esac
program_words=$(python3 - "$program_file" <<'PYTHON'
import pathlib
import re
import sys

words = pathlib.Path(sys.argv[1]).read_text().split()
if not 1 <= len(words) <= 4096 or any(not re.fullmatch(r'[0-9a-fA-F]{8}', word) for word in words):
    raise SystemExit('Programa deve conter de 1 a 4096 palavras hexadecimais de 32 bits.')
print(len(words))
PYTHON
)
mkdir -p .build/synth
run_dir=$(mktemp -d .build/synth/run.XXXXXX)
echo "Precheck preliminar: $run_dir (modo=$mode, core=$core, showcase=$showcase, $program_words palavras)"
yosys -V > "$run_dir/version.txt"
cat > "$run_dir/mode.txt" <<MODE
mode=$mode
USE_PROGRAMMABLE_CORE=$core
SHOWCASE=$showcase
USE_ACTIVE_FETCH=$active
PROGRAM_WORDS=$program_words
PROGRAM_FILE=$program_file
MODE

run_yosys() {
    local stage="$1"
    yosys -Q -T -s "$run_dir/$stage.ys" > "$run_dir/$stage.log" 2>&1 || {
        local result=$?
        tail -n 60 "$run_dir/$stage.log" >&2
        return "$result"
    }
}

cat > "$run_dir/structure.ys" <<YOSYS
read_verilog -sv *.v
chparam -set USE_PROGRAMMABLE_CORE $core -set SHOWCASE $showcase -set USE_ACTIVE_FETCH $active -set PROGRAM_WORDS $program_words -set PROGRAM_FILE "$program_file" gpu_de1_soc_top
hierarchy -check -top gpu_de1_soc_top
proc
opt
memory_dff
memory_share
memory_collect
opt_clean
check -assert
stat
write_json $run_dir/structure.json
write_rtlil $run_dir/structure.il
YOSYS
run_yosys structure
echo 'Estrutura: hierarquia, drivers e memorias verificados.'
if (( structure_only )); then
    echo "Estatisticas estruturais: $run_dir/structure.log"
    exit 0
fi

# Guardar este auxiliar no build mantem a verificacao reproduzivel.
cat > "$run_dir/check_ram.py" <<'PYTHON'
import collections
import json
import sys

data = json.load(open(sys.argv[1]))
top = data['modules']['gpu_de1_soc_top']
counts = collections.Counter(c['type'] for c in top.get('cells', {}).values())
remaining = []
for name, cell in top.get('cells', {}).items():
    if cell['type'].startswith('$mem'):
        p = cell.get('parameters', {})
        bits = int(p.get('WIDTH', '0'), 2) * int(p.get('SIZE', '0'), 2)
        remaining.append((name, bits))
lines = ['Mapeamento de memoria preliminar Cyclone V:']
lines += [f'  {kind}: {count}' for kind, count in sorted(counts.items())
          if 'MISTRAL' in kind or 'bram' in kind.lower() or 'mlab' in kind.lower()]
lines += [f'  RAM restante {name}: {bits} bits' for name, bits in remaining]
lines += [f'  Total de bits em RAM nao mapeada: {sum(bits for _, bits in remaining)}']
text = '\n'.join(lines) + '\n'
open(sys.argv[2], 'w').write(text)
print(text, end='')
# Pequenas tabelas podem virar FFs; framebuffers/ROMs grandes nao.
if any(bits > 8192 for _, bits in remaining) or sum(bits for _, bits in remaining) > 65536:
    print('Precheck interrompido: RAM grande sem inferencia de bloco. Corrigir o RTL/avaliar o Quartus antes de expandir em FFs.', file=sys.stderr)
    sys.exit(1)
PYTHON

cat > "$run_dir/mapped.ys" <<YOSYS
read_rtlil $run_dir/structure.il
synth_intel_alm -top gpu_de1_soc_top -family cyclonev -run begin:map_lutram
stat
write_json $run_dir/ram.json
exec -expect-return 0 -- python3 $run_dir/check_ram.py $run_dir/ram.json $run_dir/ram-summary.txt
synth_intel_alm -top gpu_de1_soc_top -family cyclonev -run map_ffram:check
check -assert
stat
write_json $run_dir/mapped.json
YOSYS
run_yosys mapped
cat "$run_dir/ram-summary.txt"
python3 - "$run_dir/mapped.json" "$run_dir/mapped-summary.txt" <<'PYTHON'
import collections
import json
import sys

cells = json.load(open(sys.argv[1]))['modules']['gpu_de1_soc_top']['cells']
counts = collections.Counter(c['type'] for c in cells.values())
blocks = collections.Counter(name.split('.')[0] for name, cell in cells.items()
                             if cell['type'] == 'MISTRAL_M10K')
lines = ['Recursos apos otimizacao final (preliminares; nao sao ALMs do fitter):']
lines += [f'  {kind}: {count}' for kind, count in sorted(counts.items())
          if kind.startswith('MISTRAL_')]
lines += [f'  M10K em {name}: {count}' for name, count in sorted(blocks.items())]
text = '\n'.join(lines) + '\n'
open(sys.argv[2], 'w').write(text)
print(text, end='')
PYTHON
echo "Mapeamento preliminar concluido. Relatorios: $run_dir/{structure,mapped}.log"
echo 'Quartus/fitting, timing externo e demonstracao na placa continuam necessarios.'
