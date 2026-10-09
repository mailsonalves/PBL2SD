#!/usr/bin/env python3
"""Golden encodings, relocation, input validation and reproducible CLI checks."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "assemble.py"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("pbl2_assembler", SCRIPT)
assembler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembler)


class EncodingTests(unittest.TestCase):
    def test_canonical_instruction_golden_words(self):
        source = """
            LDI R1, 0xABC
            ADD R1, R2, R3
            SUB R4, R5, R6
            AND R7, R8, R9
            OR R10, R11, R12
            XOR R13, R14, R15
            SHL R1, R1, R0
            SHR R2, R3, R4
            CMP R5, R6
            MOV R7, R8
            ADDI R9, R10, -2
            IN R11, 2
            STATUS R12
            CLRE
            LUI R13, 0xBEEF
            ORI R14, R15, 0x8000
            CMD R15
            WAIT_FRAME
            OUT 0, R1
            HALT
        """
        expected = [0x20100ABC, 0x21123000, 0x22456000, 0x23789000,
                    0x24ABC000, 0x25DEF000, 0x26110000, 0x27234000,
                    0x28056000, 0x29780000, 0x2A9AFFFE, 0x2BB20000,
                    0x2CC00000, 0x2D000000, 0x2ED0BEEF, 0x2FEF8000,
                    0x4F000000, 0xE0000000, 0xE6100000, 0xF0000000]
        self.assertEqual(assembler.assemble(source)[0], expected)

    def test_graphics_golden_words(self):
        source = """
            CLEAR
            PALETTE 255, 0xF800
            TILE 39, 29, 255
            SCROLL 511, 255
            SPRPOS 31, 511, 255
            SPRATTR 31, 255, 1, 1, 1
            SPRSTYLE 31, 3, 1, 15
            V0 511, 255
            V1 511, 255
            TRI 511, 255, 255
            BUFFER 1
            PRESENT
            HALT
        """
        expected = [0x0F000000, 0x10FFF800, 0x30271DFF, 0x5001FFFF,
                    0xAFFFFFC0, 0xBFFFF000, 0xCFFF0000, 0x7001FFFF,
                    0x8001FFFF, 0x9FF1FFFF, 0xD0000001, 0xD1000000,
                    0xF0000000]
        self.assertEqual(assembler.assemble(source)[0], expected)

    def test_li_boundaries_and_signed_words(self):
        words, _ = assembler.assemble("""
            LI R0, 0
            LI R1, 0xFFFFF
            LI R2, 0x100000
            LI R3, -1
            LI R4, -2147483648
            LI R5, 4294967295
            .word -2147483648
            .word -1
            .word 0x2D000001
        """)
        self.assertEqual(words, [0x20000000, 0x201FFFFF,
                                 0x2E200010, 0x2F220000,
                                 0x2E30FFFF, 0x2F33FFFF,
                                 0x2E408000, 0x2F440000,
                                 0x2E50FFFF, 0x2F55FFFF,
                                 0x80000000, 0xFFFFFFFF, 0x2D000001])

    def test_labels_resolve_after_li_expansion_and_all_branches(self):
        source = """
            ; addresses count instruction words rather than source lines
            first: LI r1, 0x12345678 # expands to two words
            alias: next: LDI R0, 0b0
            JMP finish
            BEQ first
            BNE next
            BLT alias
            BGE 8
            finish: halt
        """
        words, labels = assembler.assemble(source)
        self.assertEqual(labels, {"first": 0, "alias": 2, "next": 2, "finish": 8})
        self.assertEqual(words, [0x2E101234, 0x2F115678, 0x20000000,
                                 0xE1000008, 0xE2000000, 0xE3000002,
                                 0xE4000002, 0xE5000008, 0xF0000000])

    def test_committed_core_fixture_matches_source(self):
        words, labels = assembler.assemble((ROOT / "programs/core_validation.asm").read_text())
        expected = [int(line, 16) for line in (ROOT / "programs/core_validation.hex").read_text().splitlines()]
        self.assertEqual(words, expected)
        self.assertEqual(len(words), 54)
        self.assertEqual(words[labels["failure"]:], [0xE6000000, 0xF0000000])


class ValidationTests(unittest.TestCase):
    def assert_bad(self, source, message):
        with self.assertRaisesRegex(assembler.AssemblyError, message):
            assembler.assemble(source)

    def test_invalid_operands_and_ranges(self):
        cases = [
            ("ADD R1,R2", "expects 3"), ("LDI R1,", "missing operand"),
            ("ADD R1,,R2,R3", "missing operand"), ("ADD R16,R0,R0", "R0..R15"),
            ("MOV RX,R1", "R0..R15"), ("LDI R1,-1", "LDI immediate"),
            ("LDI R1,1048576", "LDI immediate"), ("LI R1,4294967296", "32-bit value"),
            ("LI R1,-2147483649", "32-bit value"), (".word 0x100000000", "32-bit value"),
            ("ADDI R1,R2,32768", "ADDI immediate"), ("ADDI R1,R2,-32769", "ADDI immediate"),
            ("LUI R1,65536", "LUI immediate"), ("ORI R1,R2,-1", "ORI immediate"),
            ("IN R1,3", "input port"), ("OUT 1,R1", "output port"),
            ("TILE 40,0,1", "tile X"), ("TILE 0,30,1", "tile Y"),
            ("PALETTE 256,0", "palette index"), ("PALETTE 1,65536", "RGB565"),
            ("SPRPOS 32,0,0", "sprite ID"), ("SPRPOS 0,512,0", "sprite X"),
            ("SPRATTR 0,1,2,0,0", "enable"), ("SPRATTR 0,1,1,2,0", "horizontal flip"),
            ("SPRSTYLE 0,4,1,0", "sprite priority"), ("SPRSTYLE 0,1,1,16", "palette bank"),
            ("BUFFER 2", "double-buffer mode"), ("WAIT_FRAME 0", "expects 0"),
            ("NOP", "unknown instruction"), ("LDI R1,0xGG", "expected integer"),
        ]
        for source, message in cases:
            with self.subTest(source=source):
                self.assert_bad(source, message)

    def test_label_errors_and_line_numbers(self):
        self.assert_bad("HALT\nlabel: HALT\nlabel: HALT", "line 3: duplicate label")
        self.assert_bad("\nJMP missing\nHALT", "line 2: undefined label")
        self.assert_bad("JMP 2\nHALT", "outside program")
        self.assert_bad("JMP -1\nHALT", "outside program")
        self.assert_bad("JMP end\nHALT\nend:", "outside program")
        self.assert_bad("1invalid: HALT", "invalid label syntax")
        self.assert_bad("# empty\n; comments only", "no instructions")

    def test_memory_capacity_includes_expanded_words(self):
        source = "HALT\n" * 4096
        self.assertEqual(len(assembler.assemble(source)[0]), 4096)
        self.assert_bad(source + "HALT\n", "line 4097: program exceeds 4096")
        self.assert_bad("HALT\n" * 4095 + "LI R1,0x12345678", "line 4096: program exceeds 4096")


class CliTests(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)], capture_output=True, text=True)

    def test_output_symbols_and_non_destructive_check(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            source = directory / "example.asm"
            output = directory / "example.hex"
            symbols = directory / "example.json"
            source.write_text("entry: LI R1,0x12345678\nJMP entry\n")
            result = self.run_cli(source, "--symbols", symbols)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(), "2E101234\n2F115678\nE1000000\n")
            self.assertEqual(json.loads(symbols.read_text()), {"entry": 0})
            original_mtimes = (output.stat().st_mtime_ns, symbols.stat().st_mtime_ns)
            result = self.run_cli(source, "--check", "--symbols", symbols)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS: checked 3 words", result.stdout)
            self.assertEqual((output.stat().st_mtime_ns, symbols.stat().st_mtime_ns), original_mtimes)
            output.write_text("00000000\n2F115678\nE1000000\n")
            original = output.read_bytes()
            result = self.run_cli(source, "--check")
            self.assertEqual(result.returncode, 1)
            self.assertIn("first difference at word 0", result.stderr)
            self.assertEqual(output.read_bytes(), original)

    def test_cli_failures_preserve_existing_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            source = directory / "invalid.asm"
            output = directory / "existing.hex"
            source.write_text("LDI R16,1\n")
            output.write_text("F0000000\n")
            result = self.run_cli(source, "-o", output)
            self.assertEqual(result.returncode, 1)
            self.assertIn("line 1:", result.stderr)
            self.assertEqual(output.read_text(), "F0000000\n")
            source.write_text("HALT\n")
            result = self.run_cli(source, "-o", source)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(source.read_text(), "HALT\n")
            result = self.run_cli(source, "--check")
            self.assertEqual(result.returncode, 1)
            self.assertIn("No such file", result.stderr)

    def test_cli_check_detects_length_and_bad_hex(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            source = directory / "example.asm"
            output = directory / "example.hex"
            source.write_text("HALT\n")
            for contents, diagnostic in [("F0000000\nF0000000\n", "first difference at word 1"),
                                         ("", "first difference at word 0"),
                                         ("garbage\n", "eight-digit hexadecimal")]:
                with self.subTest(contents=contents):
                    output.write_text(contents)
                    result = self.run_cli(source, "--check")
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(diagnostic, result.stderr)
                    self.assertEqual(output.read_text(), contents)


if __name__ == "__main__":
    unittest.main()
