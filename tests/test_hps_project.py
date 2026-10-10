"""Validate isolated HPS project preparation without Quartus or physical MMIO.

The Tcl recorder and HDL stub check the intended integration contract. They do
not generate Intel IP or establish that the generated system boots on the board.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / 'scripts' / 'prepare_hps.py'
TEMPLATES = ('create_system.tcl', 'de1_soc_hps_parameters.tcl',
             'pbl2_hps_top.v', 'hps_pins.qsf', 'LICENSE.fpgacademy', 'reference.json')


def snapshot(directory):
    return {str(path.relative_to(directory)): path.read_bytes()
            for path in directory.rglob('*') if path.is_file()}


def system_ports():
    """Independent contract for the exported Platform Designer interfaces."""
    ports = {
        'clk_clk': ('input', 1), 'reset_reset_n': ('input', 1),
        'gpu_board_key': ('input', 4), 'gpu_board_switches': ('input', 10),
        'gpu_board_leds': ('output', 10),
    }
    for name in ('hs', 'vs', 'blank_n', 'sync_n', 'pixel_clk'):
        ports['gpu_vga_' + name] = ('output', 1)
    for name in ('r', 'g', 'b'):
        ports['gpu_vga_' + name] = ('output', 8)
    for name, width in (('a', 15), ('ba', 3), ('dm', 4), ('ck', 1),
                        ('ck_n', 1), ('cke', 1), ('cs_n', 1), ('ras_n', 1),
                        ('cas_n', 1), ('we_n', 1), ('reset_n', 1), ('odt', 1)):
        ports['memory_mem_' + name] = ('output', width)
    for name, width in (('dq', 32), ('dqs', 4), ('dqs_n', 4)):
        ports['memory_mem_' + name] = ('inout', width)
    ports['memory_oct_rzqin'] = ('input', 1)
    groups = {
        'emac1': {
            'output': ['TX_CLK', 'MDC', 'TX_CTL', *['TXD' + str(i) for i in range(4)]],
            'input': ['RX_CLK', 'RX_CTL', *['RXD' + str(i) for i in range(4)]],
            'inout': ['MDIO'],
        },
        'qspi': {'output': ['SS0', 'CLK'], 'inout': ['IO' + str(i) for i in range(4)]},
        'i2c0': {'inout': ['SDA', 'SCL']}, 'i2c1': {'inout': ['SDA', 'SCL']},
        'sdio': {'output': ['CLK'], 'inout': ['CMD', *['D' + str(i) for i in range(4)]]},
        'spim1': {'output': ['CLK', 'MOSI'], 'input': ['MISO'], 'inout': ['SS0']},
        'uart0': {'input': ['RX'], 'output': ['TX']},
        'usb1': {'input': ['CLK', 'DIR', 'NXT'], 'output': ['STP'],
                 'inout': ['D' + str(i) for i in range(8)]},
        'gpio': {'inout': [f'GPIO{i:02d}' for i in (9, 35, 40, 41, 48, 53, 54, 61)]},
    }
    for group, directions in groups.items():
        for direction, names in directions.items():
            for name in names:
                ports[f'hps_io_hps_io_{group}_inst_{name}'] = (direction, 1)
    return ports


class HpsProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('prepare_hps', HELPER)
        cls.helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.helper)

    def fixture(self, parent):
        """Small temporary source repository; failure tests never delete real files."""
        repo = parent / 'repo'
        (repo / 'platform').mkdir(parents=True)
        shutil.copytree(REPO / 'platform' / 'hps', repo / 'platform' / 'hps')
        shutil.copy2(REPO / 'platform' / 'gpu_mmio_hw.tcl', repo / 'platform')
        shutil.copy2(REPO / 'gpu.sdc', repo / 'gpu.sdc')
        (repo / 'programs').mkdir()
        (repo / 'programs' / 'demo.hex').write_text('F0000000\n')
        (repo / 'sample.v').write_text('module sample; endmodule\n')
        (repo / 'sample.hex').write_text('00\n')
        (repo / 'sample.mif').write_text('DEPTH = 1;\nWIDTH = 8;\n')
        (repo / 'gpu.qsf').write_text('\n'.join([
            'set_global_assignment -name TOP_LEVEL_ENTITY old_top',
            'set_global_assignment -name VERILOG_FILE old_top.v',
            'set_global_assignment -name QIP_FILE old_system.qip',
            'set_global_assignment -name SEARCH_PATH old_platform',
            'set_parameter -name PROGRAM_WORDS 17',
            'set_location_assignment PIN_AF14 -to CLOCK_50',
            'set_location_assignment PIN_AA14 -to KEY[0]',
            'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to {SW[*]}',
            'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDR*',
            'set_location_assignment PIN_A13 -to VGA_R[0]',
            'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to "VGA_*"',
            'set_location_assignment PIN_A1 -to HPS_DDR3_DQ[0]',
            'set_location_assignment PIN_A2 -to HEX0[0]',
            'set_location_assignment PIN_A3 -to KEY[0]garbage',
            'set_location_assignment PIN_A4 -to VGA_FAKE',
            'set_instance_assignment -name PARTITION_HIERARCHY root_partition -to |',
        ]) + '\n')
        return repo

    def test_import_has_no_output_or_filesystem_side_effects(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            repo = self.fixture(parent)
            (repo / 'scripts').mkdir()
            shutil.copy2(HELPER, repo / 'scripts' / HELPER.name)
            before = snapshot(repo)
            result = subprocess.run([sys.executable, '-B', '-c',
                                     'import importlib.util, sys; '
                                     's=importlib.util.spec_from_file_location("setup", sys.argv[1]); '
                                     'm=importlib.util.module_from_spec(s); s.loader.exec_module(m)',
                                     str(repo / 'scripts' / HELPER.name)],
                                    cwd=parent, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, '')
            self.assertEqual(result.stderr, '')
            self.assertEqual(snapshot(repo), before)

    def test_copied_project_preserves_source_assets_and_sdc(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            repo = self.fixture(parent)
            before = snapshot(repo)
            output = self.helper.prepare_project(repo, parent / 'output')
            for name in ('sample.v', 'sample.hex', 'sample.mif', 'gpu.sdc'):
                self.assertEqual((output / name).read_bytes(), before[name])
            self.assertEqual(snapshot(output / 'programs'), snapshot(repo / 'programs'))
            self.assertEqual(snapshot(output / 'hps'), snapshot(repo / 'platform' / 'hps'))
            self.assertEqual((output / 'platform' / 'gpu_mmio_hw.tcl').read_bytes(),
                             before['platform/gpu_mmio_hw.tcl'])
            self.assertEqual(snapshot(repo), before)
            self.assertFalse((output / 'pbl2_hps_system.qsys').exists())
            self.assertFalse((output / 'pbl2_hps_system').exists())

    def test_qsf_has_one_top_and_retains_only_fpga_board_assignments(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            repo = self.fixture(parent)
            output = self.helper.prepare_project(repo, parent / 'output')
            qsf = (output / 'pbl2_hps.qsf').read_text()
            self.assertEqual((output / 'pbl2_hps.qpf').read_text(),
                             'PROJECT_REVISION = "pbl2_hps"\n')
            expected = {'DEVICE': '5CSEMA5F31C6', 'TOP_LEVEL_ENTITY': 'pbl2_hps_top',
                        'QIP_FILE': 'pbl2_hps_system/synthesis/pbl2_hps_system.qip',
                        'SEARCH_PATH': 'platform', 'SDC_FILE': 'gpu.sdc',
                        'VERILOG_FILE': 'hps/pbl2_hps_top.v'}
            for assignment, value in expected.items():
                self.assertEqual(re.findall(rf'^set_global_assignment -name {assignment} (.+)$',
                                            qsf, re.MULTILINE), [value])
            pins = [line for line in qsf.splitlines()
                    if line.startswith(('set_location_assignment ', 'set_instance_assignment '))]
            original_pins = [line for line in (repo / 'gpu.qsf').read_text().splitlines()
                             if re.search(r'-to (CLOCK_50|KEY\[0\]|\{SW\[\*\]\}|LEDR\*|VGA_R\[0\]|"VGA_\*")$', line)]
            self.assertEqual(pins, original_pins)
            self.assertIn('source hps/hps_pins.qsf\n', qsf)
            self.assertNotIn('set_parameter', qsf)

    def test_default_outputs_are_unique_under_repository_build_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = self.fixture(Path(temporary))
            first = self.helper.prepare_project(repo)
            second = self.helper.prepare_project(repo)
            self.assertNotEqual(first, second)
            for output in (first, second):
                self.assertEqual(output.parent, repo / '.build' / 'hps')
                self.assertTrue(output.name.startswith('run.'))
                self.assertTrue((output / 'pbl2_hps.qsf').is_file())

    def test_existing_output_is_rejected_without_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            repo = self.fixture(parent)
            output = parent / 'output'
            output.mkdir()
            (output / 'keep.txt').write_text('existing user work\n')
            before = snapshot(parent)
            with self.assertRaises(FileExistsError):
                self.helper.prepare_project(repo, output)
            self.assertEqual(snapshot(parent), before)

    def test_dangling_output_symlink_is_rejected_without_following_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            repo = self.fixture(parent)
            target = parent / 'missing-output'
            output = parent / 'output'
            output.symlink_to(target, target_is_directory=True)
            before = snapshot(repo)
            with self.assertRaises(FileExistsError):
                self.helper.prepare_project(repo, output)
            self.assertTrue(output.is_symlink())
            self.assertFalse(target.exists())
            self.assertEqual(snapshot(repo), before)

    def test_missing_inputs_fail_before_any_output_creation(self):
        missing_inputs = ['platform/hps/' + name for name in TEMPLATES]
        missing_inputs += ['platform/gpu_mmio_hw.tcl', 'gpu.qsf', 'gpu.sdc', 'programs']
        for missing in missing_inputs:
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as temporary:
                parent = Path(temporary)
                repo = self.fixture(parent)
                path = repo / missing
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
                for output in (None, parent / 'new-parent' / 'output'):
                    with self.assertRaises(FileNotFoundError) as failure:
                        self.helper.prepare_project(repo, output)
                    self.assertIn(str(path), str(failure.exception))
                    self.assertFalse((repo / '.build').exists())
                    self.assertFalse((parent / 'new-parent').exists())

    def test_output_inside_copied_source_trees_is_rejected(self):
        for tree in ('programs', 'platform/hps'):
            with self.subTest(tree=tree), tempfile.TemporaryDirectory() as temporary:
                repo = self.fixture(Path(temporary))
                before = snapshot(repo)
                with self.assertRaises(ValueError):
                    self.helper.prepare_project(repo, repo / tree / 'nested' / 'output')
                self.assertEqual(snapshot(repo), before)

    def test_actual_repository_copy_is_self_contained(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = self.helper.prepare_project(REPO, Path(temporary) / 'output')
            for pattern in ('*.v', '*.hex', '*.mif'):
                for source in REPO.glob(pattern):
                    if source.is_file():
                        self.assertEqual((output / source.name).read_bytes(), source.read_bytes())
            self.assertEqual((output / 'gpu.sdc').read_bytes(), (REPO / 'gpu.sdc').read_bytes())
            self.assertEqual(snapshot(output / 'programs'), snapshot(REPO / 'programs'))
            self.assertEqual(snapshot(output / 'hps'), snapshot(REPO / 'platform' / 'hps'))
            self.assertNotIn(str(REPO), (output / 'pbl2_hps.qsf').read_text())

    def test_cli_prepares_from_another_directory_and_rejects_existing_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = parent / 'project with spaces'
            command = [sys.executable, '-B', str(HELPER), '--out', str(output)]
            result = subprocess.run(command, cwd=parent, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(str(output), result.stdout)
            self.assertTrue((output / 'pbl2_hps.qsf').is_file())
            before = snapshot(output)
            result = subprocess.run(command, cwd=parent, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(snapshot(output), before)
            self.assertFalse((output / 'pbl2_hps_system.qsys').exists())

    def test_create_system_tcl_connects_lightweight_gpu_and_both_resets(self):
        self.assertIsNotNone(shutil.which('tclsh'), 'Tcl is required')
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = self.helper.prepare_project(REPO, parent / 'output')
            recorder = parent / 'record.tcl'
            recorder.write_text('''package provide qsys 1.0
foreach command {create_system set_project_property add_instance
    set_instance_parameter_value add_connection set_connection_parameter_value
    set_interface_property save_system} {
    proc $command {args} [format {puts [join [list EVENT %s {*}$args] "\\t"]} $command]
}
if {[catch {source [lindex $argv 0]} failure]} {
    puts stderr $failure
    exit 1
}
''')
            result = subprocess.run(['tclsh', str(recorder), str(output / 'hps' / 'create_system.tcl')],
                                    cwd=output, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            events = [line.split('\t')[1:] for line in result.stdout.splitlines()
                      if line.startswith('EVENT\t')]
            self.assertIn(['create_system', 'pbl2_hps_system'], events)
            self.assertIn(['set_project_property', 'DEVICE', '5CSEMA5F31C6'], events)
            instances = [event[1:] for event in events if event[0] == 'add_instance']
            self.assertEqual(instances, [['clk_0', 'clock_source'],
                                         ['ARM_A9_HPS', 'altera_hps'], ['gpu', 'pbl2_gpu', '1.0']])
            connections = {tuple(event[1:]) for event in events if event[0] == 'add_connection'}
            self.assertEqual(connections, {
                ('clk_0.clk', 'ARM_A9_HPS.h2f_axi_clock'),
                ('clk_0.clk', 'ARM_A9_HPS.f2h_axi_clock'),
                ('clk_0.clk', 'ARM_A9_HPS.h2f_lw_axi_clock'),
                ('clk_0.clk', 'gpu.clock'), ('clk_0.clk_reset', 'gpu.reset'),
                ('ARM_A9_HPS.h2f_reset', 'gpu.reset'),
                ('ARM_A9_HPS.h2f_lw_axi_master', 'gpu.control'),
            })
            self.assertIn(['set_connection_parameter_value',
                           'ARM_A9_HPS.h2f_lw_axi_master/gpu.control', 'baseAddress', '0x00000000'], events)
            parameters = {(event[1], event[2]): event[3] for event in events
                          if event[0] == 'set_instance_parameter_value'}
            self.assertEqual(parameters[('clk_0', 'clockFrequency')], '50000000')
            expected = {'LWH2F_Enable': 'true', 'F2SINTERRUPT_Enable': 'false',
                        'MEM_CLK_FREQ': '400.0', 'MEM_DQ_WIDTH': '32',
                        'MEM_ROW_ADDR_WIDTH': '15', 'MEM_COL_ADDR_WIDTH': '10',
                        'MEM_VENDOR': 'Micron', 'MEM_TCL': '7', 'MEM_TRCD_NS': '13.125',
                        'MEM_TRP_NS': '13.125', 'MEM_TRFC_NS': '300.0',
                        'MEM_DRV_STR': 'RZQ/6', 'MEM_RTT_NOM': 'RZQ/6'}
            for name, value in expected.items():
                self.assertEqual(parameters[('ARM_A9_HPS', name)], value, name)
            enabled_gpio = parameters[('ARM_A9_HPS', 'GPIO_Enable')].split()
            self.assertEqual([i for i, enabled in enumerate(enabled_gpio) if enabled == 'Yes'],
                             [9, 35, 40, 41, 48, 53, 54, 61])
            self.assertEqual(parameters[('gpu', 'PROGRAM_WORDS')], '256')
            self.assertEqual(parameters[('gpu', 'PROGRAM_FILE')], 'programs/background_motion.hex')
            exports = {event[1]: event[3] for event in events if event[0] == 'set_interface_property'
                       and event[2] == 'EXPORT_OF'}
            self.assertEqual(exports, {'clk': 'clk_0.clk_in', 'reset': 'clk_0.clk_in_reset',
                                      'memory': 'ARM_A9_HPS.memory', 'hps_io': 'ARM_A9_HPS.hps_io',
                                      'gpu_board': 'gpu.board', 'gpu_vga': 'gpu.vga'})
            self.assertIn(['save_system', 'pbl2_hps_system.qsys'], events)

    def test_board_reference_is_pinned_and_ddr_constraints_are_present(self):
        directory = REPO / 'platform' / 'hps'
        reference = json.loads((directory / 'reference.json').read_text())
        self.assertEqual(reference['repository'], 'https://github.com/fpgacademy/Design_Examples')
        self.assertRegex(reference['commit'], r'^[0-9a-f]{40}$')
        self.assertEqual(reference['license'], 'MIT')
        sources = {source['file']: source for source in reference['sources']}
        for name in ('LICENSE', 'common.tcl', 'de1_hps_board.tcl',
                     'DE1_SoC_ARM_NiosII_Computer.v', 'DE1_SoC_ARM_NiosII_Computer.qsf'):
            source = sources[name]
            self.assertIn('/' + reference['commit'] + '/', source['url'])
            self.assertTrue(source['url'].startswith('https://raw.githubusercontent.com/fpgacademy/Design_Examples/'))
            self.assertRegex(source['sha256'], r'^[0-9a-f]{64}$')
            self.assertGreater(source['bytes'], 0)
        license_bytes = (directory / 'LICENSE.fpgacademy').read_bytes()
        self.assertEqual(hashlib.sha256(license_bytes).hexdigest(), sources['LICENSE']['sha256'])
        self.assertEqual(len(license_bytes), sources['LICENSE']['bytes'])
        pins = (directory / 'hps_pins.qsf').read_text()
        for index in range(32):
            self.assertIn(f'IO_STANDARD "SSTL-15 CLASS I" -to {{HPS_DDR3_DQ[{index}]}}', pins)
            self.assertIn(f'INPUT_TERMINATION "PARALLEL 50 OHM WITH CALIBRATION" -to {{HPS_DDR3_DQ[{index}]}}', pins)
        for index in range(4):
            for side in ('N', 'P'):
                self.assertIn(f'IO_STANDARD "DIFFERENTIAL 1.5-V SSTL CLASS I" -to {{HPS_DDR3_DQS_{side}[{index}]}}', pins)
        self.assertNotIn('set_location_assignment', pins)

    def test_hps_pin_constraints_source_as_tcl_with_literal_bus_targets(self):
        self.assertIsNotNone(shutil.which('tclsh'), 'Tcl is required')
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = self.helper.prepare_project(REPO, parent / 'output')
            recorder = parent / 'pin_record.tcl'
            recorder.write_text('''proc set_instance_assignment {args} {
    puts [join [list PIN {*}$args] "\\t"]
}
if {[catch {source [lindex $argv 0]} failure]} {
    puts stderr $failure
    exit 1
}
''')
            result = subprocess.run(['tclsh', str(recorder), str(output / 'hps' / 'hps_pins.qsf')],
                                    cwd=output, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = [line.split('\t')[1:] for line in result.stdout.splitlines()]
            self.assertEqual(len(calls), 312)
            self.assertTrue(all(len(call) == 5 and call[0] == '-name' and call[3] == '-to'
                                and call[4].startswith('HPS_') for call in calls))
            top_header = (output / 'hps' / 'pbl2_hps_top.v').read_text().split(');', 1)[0]
            top_ports = {
                name: (int(low), int(high)) if high else (0, 0)
                for high, low, name in re.findall(
                    r'\b(?:input|output|inout)\s+wire\s*(?:\[(\d+):(\d+)\]\s*)?(\w+)',
                    top_header)
            }
            for call in calls:
                target = call[4]
                match = re.fullmatch(r'(HPS_\w+)(?:\[(\d+)\])?', target)
                self.assertIsNotNone(match, f'Unsupported HPS pin target: {target}')
                name, index = match.groups()
                self.assertIn(name, top_ports, f'Constraint has no top port: {target}')
                if index is not None:
                    low, high = top_ports[name]
                    self.assertGreaterEqual(int(index), low, target)
                    self.assertLessEqual(int(index), high, target)
            for index in range(2):
                self.assertIn(['-name', 'IO_STANDARD', '3.3-V LVTTL', '-to',
                               f'HPS_GPIO[{index}]'], calls)
            for index in range(32):
                self.assertIn(['-name', 'IO_STANDARD', 'SSTL-15 CLASS I', '-to',
                               f'HPS_DDR3_DQ[{index}]'], calls)
            self.assertIn(['-name', 'IO_STANDARD', 'DIFFERENTIAL 1.5-V SSTL CLASS I',
                           '-to', 'HPS_DDR3_DQS_P[3]'], calls)

    def test_top_elaborates_against_export_contract_and_routes_board_signals(self):
        self.assertIsNotNone(shutil.which('iverilog'), 'Icarus Verilog is required')
        self.assertIsNotNone(shutil.which('vvp'), 'Icarus Verilog is required')
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = self.helper.prepare_project(REPO, parent / 'output')
            top = output / 'hps' / 'pbl2_hps_top.v'
            connections = dict(re.findall(r'\.(\w+)\(\s*([^()]+?)\s*\)', top.read_text()))
            ports = system_ports()
            self.assertEqual(set(connections), set(ports))
            self.assertEqual(connections['memory_mem_a'], 'HPS_DDR3_ADDR')
            self.assertEqual(connections['memory_mem_dq'], 'HPS_DDR3_DQ')
            self.assertEqual(connections['memory_mem_dqs'], 'HPS_DDR3_DQS_P')
            self.assertEqual(connections['memory_mem_dqs_n'], 'HPS_DDR3_DQS_N')
            declarations = [f'{direction} wire ' + (f'[{width - 1}:0] ' if width > 1 else '') + name
                            for name, (direction, width) in ports.items()]
            stub = parent / 'system_stub.v'
            stub.write_text('module pbl2_hps_system(\n' + ',\n'.join(declarations) + ''');
assign gpu_board_leds = reset_reset_n ? gpu_board_switches : 10'd0;
assign gpu_vga_r = 8'h12;
assign gpu_vga_g = 8'h34;
assign gpu_vga_b = 8'h56;
assign gpu_vga_hs = 1'b1;
assign gpu_vga_vs = 1'b0;
assign gpu_vga_blank_n = 1'b1;
assign gpu_vga_sync_n = 1'b0;
assign gpu_vga_pixel_clk = clk_clk;
endmodule
''')
            bench = parent / 'top_test.sv'
            bench.write_text('''`timescale 1ns/1ps
module tb_hps_top;
reg clk = 0;
reg [3:0] key = 4'hf;
reg [9:0] switches = 10'h2a5;
wire [9:0] leds;
wire [7:0] red, green, blue;
wire pixel_clk, hs, vs, blank_n, sync_n;
pbl2_hps_top dut(.CLOCK_50(clk), .KEY(key), .SW(switches), .LEDR(leds),
    .VGA_R(red), .VGA_G(green), .VGA_B(blue), .VGA_CLK(pixel_clk),
    .VGA_HS(hs), .VGA_VS(vs), .VGA_BLANK_N(blank_n), .VGA_SYNC_N(sync_n));
initial begin
    #1;
    if (leds !== switches || dut.u_system.gpu_board_key !== key)
        $fatal(1, "board conduit mismatch");
    if ({red,green,blue,hs,vs,blank_n,sync_n} !== {24'h123456,4'b1010})
        $fatal(1, "VGA conduit mismatch");
    clk = 1; key = 4'h6; #1;
    if (pixel_clk !== 1 || dut.u_system.gpu_board_key !== key || leds !== 0)
        $fatal(1, "clock/reset conduit mismatch");
    key = 4'h9; switches = 10'h155; clk = 0; #1;
    if (pixel_clk !== 0 || leds !== switches)
        $fatal(1, "board conduit update mismatch");
    $display("PASS HPS top export contract (stub only)");
    $finish;
end
endmodule
''')
            executable = parent / 'top.vvp'
            result = subprocess.run(['iverilog', '-g2012', '-s', 'tb_hps_top', '-o',
                                     str(executable), str(top), str(stub), str(bench)],
                                    cwd=output, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run(['vvp', str(executable)], cwd=output,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS HPS top export contract (stub only)', result.stdout)


if __name__ == '__main__':
    unittest.main()
