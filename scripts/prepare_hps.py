#!/usr/bin/env python3
"""Prepare an isolated HPS project; generation/compilation require Quartus."""
import argparse
from pathlib import Path
import re
import shutil
import sys
import tempfile


HPS_TEMPLATES = (
    'create_system.tcl',
    'de1_soc_hps_parameters.tcl',
    'pbl2_hps_top.v',
    'hps_pins.qsf',
    'LICENSE.fpgacademy',
    'reference.json',
)


def fpga_pin_assignments(qsf):
    """Retain only pin assignments for the FPGA board ports of this top."""
    lines = []
    for line in qsf.splitlines():
        if not re.match(r'^\s*set_(?:location|instance)_assignment\s', line):
            continue
        match = re.search(r'\s-to\s+(\{[^}]+\}|"[^"]+"|\S+)', line)
        if not match:
            continue
        target = match.group(1).strip('{}"')
        board_target = re.fullmatch(
            r'CLOCK_50|KEY(?:\[[0-3*]\]|\*)?'
            r'|(?:SW|LEDR)(?:\[[0-9*]\]|\*)?'
            r'|VGA_(?:HS|VS|CLK|BLANK_N|SYNC_N|[RGB](?:\[[0-7*]\]|\*)?|\*)', target)
        if board_target:
            lines.append(line.strip())
    if not lines:
        raise ValueError('gpu.qsf nao contem atribuicoes dos pinos FPGA esperados')
    return lines


def validate_inputs(repo):
    """Check templates before creating any output directory."""
    required = [repo / 'platform' / 'hps' / name for name in HPS_TEMPLATES]
    required.extend((repo / 'platform' / 'gpu_mmio_hw.tcl',
                     repo / 'gpu.qsf', repo / 'gpu.sdc'))
    missing = [str(path) for path in required if not path.is_file()]
    if not (repo / 'programs').is_dir():
        missing.append(str(repo / 'programs'))
    if missing:
        raise FileNotFoundError('Arquivos de preparacao ausentes: ' + ', '.join(missing))
    return fpga_pin_assignments((repo / 'gpu.qsf').read_text())


def prepare_project(repo, out=None):
    """Copy source/assets and write project metadata without invoking tools."""
    repo = Path(repo).resolve()
    pins = validate_inputs(repo)
    if out is None:
        build = repo / '.build' / 'hps'
        build.mkdir(parents=True, exist_ok=True)
        destination = Path(tempfile.mkdtemp(prefix='run.', dir=build))
    else:
        requested = Path(out).expanduser()
        if requested.exists() or requested.is_symlink():
            raise FileExistsError('A saida ja existe: ' + str(requested))
        destination = requested.resolve()
        # copytree cannot safely copy programs/ into one of its descendants.
        for copied_tree in (repo / 'programs', repo / 'platform' / 'hps'):
            if destination == copied_tree or copied_tree in destination.parents:
                raise ValueError('A saida nao pode ficar dentro de uma arvore de fontes copiada')
        destination.mkdir(parents=True, exist_ok=False)

    try:
        for pattern in ('*.v', '*.hex', '*.mif'):
            for source in sorted(repo.glob(pattern)):
                if source.is_file():
                    shutil.copy2(source, destination / source.name)
        shutil.copytree(repo / 'programs', destination / 'programs')
        shutil.copytree(repo / 'platform' / 'hps', destination / 'hps')
        (destination / 'platform').mkdir()
        shutil.copy2(repo / 'platform' / 'gpu_mmio_hw.tcl',
                     destination / 'platform' / 'gpu_mmio_hw.tcl')
        shutil.copy2(repo / 'gpu.sdc', destination / 'gpu.sdc')
        (destination / 'pbl2_hps.qpf').write_text('PROJECT_REVISION = "pbl2_hps"\n')
        assignments = [
            '# Projeto preparado; gerar primeiro o sistema Platform Designer.',
            'set_global_assignment -name FAMILY "Cyclone V"',
            'set_global_assignment -name DEVICE 5CSEMA5F31C6',
            'set_global_assignment -name TOP_LEVEL_ENTITY pbl2_hps_top',
            'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
            'set_global_assignment -name SEARCH_PATH platform',
            'set_global_assignment -name QIP_FILE pbl2_hps_system/synthesis/pbl2_hps_system.qip',
            'set_global_assignment -name SDC_FILE gpu.sdc',
            'set_global_assignment -name VERILOG_FILE hps/pbl2_hps_top.v',
            '',
            '# RTL da GPU e assets sao incluidos pelo QIP/componente customizado.',
            *pins,
            '',
            'source hps/hps_pins.qsf',
        ]
        (destination / 'pbl2_hps.qsf').write_text('\n'.join(assignments) + '\n')
    except BaseException:
        # The destination was just created by this invocation, never reused.
        shutil.rmtree(destination)
        raise
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path,
                        help='Diretorio de saida novo; falha se ja existir.')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    try:
        destination = prepare_project(repo, args.out)
    except (OSError, ValueError) as error:
        print('Erro: ' + str(error), file=sys.stderr)
        return 1
    print('Projeto: ' + str(destination))
    return 0


if __name__ == '__main__':
    sys.exit(main())
