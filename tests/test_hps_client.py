"""Compile the Linux client and validate input before any physical MMIO access."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class HpsClientTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which('cc')
        if not compiler:
            raise RuntimeError('A C compiler is required')
        build = REPO / '.build' / 'hps-client'
        build.mkdir(parents=True, exist_ok=True)
        cls.client = build / 'gpu_load'
        subprocess.run([compiler, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic',
                        str(REPO / 'software' / 'gpu_load.c'), '-o', str(cls.client)],
                       check=True, capture_output=True, text=True)

    def test_published_programs(self):
        for name in ('program_a', 'program_b', 'background_sprites', 'polygons_motion',
                     'background_motion'):
            with self.subTest(program=name):
                result = subprocess.run([str(self.client), '--check',
                                         str(REPO / 'programs' / f'{name}.hex')],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('256 instrucoes', result.stdout)

    def test_no_wait_can_check_continuous_program_without_mmio(self):
        program = str(REPO / 'programs' / 'background_motion.hex')
        for options in (['--check', program, '--no-wait'],
                        ['--no-wait', '--check', program]):
            with self.subTest(options=options):
                result = subprocess.run([str(self.client), *options],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('HEX valido: 256 instrucoes', result.stdout)
                self.assertNotIn('/dev/mem', result.stderr)

    def test_no_wait_requires_program_and_base_for_real_access(self):
        program = str(REPO / 'programs' / 'background_motion.hex')
        for options in (['--no-wait'], ['--no-wait', '--program', program],
                        ['--no-wait', '--base', '0'], ['--no-wait', '--check'],
                        ['--no-wait', '--program'], ['--no-wait', '--base']):
            with self.subTest(options=options):
                result = subprocess.run([str(self.client), *options],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn('mapa real', result.stderr)
                self.assertNotIn('/dev/mem', result.stderr)

    def test_no_wait_rejects_bad_options_before_mmio(self):
        program = str(REPO / 'programs' / 'background_motion.hex')
        for options in (['--no-wait=1'], ['--no-wait', 'yes'],
                        ['--no-wait', '--unknown'], ['--no-wait', '--timeout-ms'],
                        ['--no-wait', '--timeout-ms', '0'],
                        ['--no-wait', '--timeout-ms', '-1'],
                        ['--no-wait', '--timeout-ms', '3600001'],
                        ['--no-wait', '--base', '0x3'],
                        ['--no-wait', '--base', 'invalid']):
            with self.subTest(options=options):
                result = subprocess.run([str(self.client), '--base', '0',
                                         '--program', program, *options],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertNotIn('/dev/mem', result.stderr)

    def test_no_wait_still_validates_hex_before_real_access(self):
        with tempfile.NamedTemporaryFile(mode='w') as file:
            file.write('not an instruction\n')
            file.flush()
            result = subprocess.run([str(self.client), '--base', '0', '--program', file.name,
                                     '--no-wait'], text=True, capture_output=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn('oito digitos HEX', result.stderr)
            self.assertNotIn('/dev/mem', result.stderr)

    def test_bad_hex_is_rejected(self):
        for content in ('', '@0000\nF0000000\n', '123456789\n', '1234567\n',
                        'F0000000 garbage\n', 'F0000000\n' * 257):
            with self.subTest(content=content[:30]), tempfile.NamedTemporaryFile(mode='w') as file:
                file.write(content)
                file.flush()
                result = subprocess.run([str(self.client), '--check', file.name],
                                        text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)

    def test_real_access_requires_valid_explicit_base(self):
        program = str(REPO / 'programs' / 'program_a.hex')
        for options in ([], ['--base', '-1'], ['--base', '0x3'],
                        ['--base', '0xffffffffffffffff'], ['--base', 'invalid']):
            with self.subTest(options=options):
                result = subprocess.run([str(self.client), '--program', program, *options],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn('mapa real', result.stderr)


if __name__ == '__main__':
    unittest.main()
