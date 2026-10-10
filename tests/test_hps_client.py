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
        subprocess.run([compiler, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                        str(REPO / 'software' / 'gpu_load.c'), '-o', str(cls.client)],
                       check=True, capture_output=True, text=True)

    def test_published_programs(self):
        for name in ('program_a', 'program_b', 'background_sprites', 'polygons_motion'):
            with self.subTest(program=name):
                result = subprocess.run([str(self.client), '--check',
                                         str(REPO / 'programs' / f'{name}.hex')],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('256 instrucoes', result.stdout)

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
