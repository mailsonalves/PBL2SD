"""Load ROMs from the actual isolated Quartus copies using four-state simulation."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class QuartusSetupTests(unittest.TestCase):
    def simulate_rom(self, project, program, words, active=1):
        self.assertIsNotNone(shutil.which('iverilog'), 'Icarus Verilog is required')
        self.assertIsNotNone(shutil.which('vvp'), 'Icarus Verilog is required')
        # PROGRAM_FILE intentionally has no instance override: use the copied HDL.
        check_rom = '''
        for (i = 0; i < WORDS; i = i + 1)
            if (^dut.u_core.gen_active_fetch.u_fetch.u_instruction_memory.memory[i] === 1'bx ||
                dut.u_core.gen_active_fetch.u_fetch.u_instruction_memory.memory[i] !== expected[i])
                $fatal(1, "Wrong or uninitialized instruction at word %0d", i);
        ''' if active else ''
        bench = f'''`timescale 1ns/1ps
module tb_quartus_rom;
    localparam WORDS = {words};
    gpu_de1_soc_top #(.PROGRAM_WORDS(WORDS), .USE_ACTIVE_FETCH({active})) dut (
        .CLOCK_50(1'b0), .KEY(4'he), .SW(10'd0));
    reg [31:0] expected [0:WORDS-1];
    integer i;
    initial begin
        $readmemh("{program}", expected);
        #1;
        if (dut.PROGRAM_FILE != "{program}") $fatal(1, "Wrong program parameter");
        {check_rom}
        $display("PASS Quartus copy ROM");
        $finish;
    end
endmodule
'''
        build = REPO / '.build' / 'quartus-setup-tests'
        build.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            testbench = Path(temporary) / 'rom.sv'
            executable = Path(temporary) / 'rom.vvp'
            testbench.write_text(bench)
            result = subprocess.run(['iverilog', '-g2012', '-s', 'tb_quartus_rom',
                                     '-o', str(executable),
                                     *map(str, sorted(project.glob('*.v'))), str(testbench)],
                                    cwd=project, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run(['vvp', str(executable)], cwd=project,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS Quartus copy ROM', result.stdout)
            self.assertNotIn('ERROR:', result.stdout + result.stderr)

    def test_project_default_loads_hex_without_qsf_string_override(self):
        self.assertNotRegex((REPO / 'gpu.qsf').read_text(),
                            r'set_parameter\s+-name\s+"?PROGRAM_FILE')
        self.simulate_rom(REPO, 'programs/background_motion.hex', 256)

    def test_generated_projects_load_each_selected_hex(self):
        originals = {name: (REPO / name).read_bytes()
                     for name in ('gpu.qsf', 'gpu_de1_soc_top.v', 'gpu_core.v')}
        cases = [([], 'programs/background_motion.hex', 256, 1),
                 (['--program', 'programs/background_sprites.hex'], 'programs/background_sprites.hex', 256, 1),
                 (['--program', 'programs/polygons_motion.hex'], 'programs/polygons_motion.hex', 256, 1),
                 (['--program', 'programs/program_a.hex'], 'programs/program_a.hex', 256, 1),
                 (['--program', 'programs/program_b.hex'], 'programs/program_b.hex', 256, 1),
                 (['--active'], 'programs/fetch_demo.hex', 9, 1),
                 (['--pbl1'], 'programs/pbl1_validation.hex', 17, 1),
                 (['--board'], 'programs/background_motion.hex', 256, 0)]
        for options, program, words, active in cases:
            with self.subTest(options=options):
                result = subprocess.run(['bash', 'scripts/synth_quartus.sh', *options,
                                         '--prepare-only'], cwd=REPO,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                match = re.search(r'^Projeto isolado: (.+)$', result.stdout, re.MULTILINE)
                self.assertIsNotNone(match, result.stdout)
                project = Path(match[1])
                qsf = (project / 'gpu.qsf').read_text()
                self.assertNotRegex(qsf, r'set_parameter\s+-name\s+"?PROGRAM_FILE')
                for name, value in [('PROGRAM_WORDS', words), ('USE_ACTIVE_FETCH', active)]:
                    values = re.findall(rf'^set_parameter -name {name} (\d+)$', qsf, re.MULTILINE)
                    self.assertEqual(int(values[-1]), value)
                self.simulate_rom(project, program, words, active)
        for name, content in originals.items():
            self.assertEqual((REPO / name).read_bytes(), content,
                             f'Preparation changed the tracked file {name}')


if __name__ == '__main__':
    unittest.main()
