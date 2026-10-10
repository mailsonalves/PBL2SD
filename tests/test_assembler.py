"""Encoding, range/error, label expansion, and reproducible-image tests."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from assemble import AssemblyError, HALT, assemble


class AssemblerTests(unittest.TestCase):
    def test_alu_golden_encodings(self):
        source = """
MOVI r15, 0xFFFF
MOV r1,r2
ADD r3,r4,r5
SUB r6,r7,r8
AND r9,r10,r11
OR r12,r13,r14
XOR r15,r1,r2
SHL r3,r4,r5
SHR r6,r7,r8
CMP r9,r10
ADDI r11,r12,-32768
ADDI r13,r14,+32767
"""
        self.assertEqual(assemble(source, words=None), [
            0x20F0FFFF, 0x21120000, 0x22345000, 0x23678000,
            0x249AB000, 0x25CDE000, 0x26F12000, 0x27345000,
            0x28678000, 0x2909A000, 0x2ABC8000, 0x2ADE7FFF])

    def test_register_graphics_golden_encodings(self):
        source = """
EMIT r15
SCROLLR r1,r2
SPR_POSR 31,r3,r4
TRI1R r5,r6
TRI2R r7,r8
TRI3R r9,r10,r11
TILER r12,r13,r14
PALETTER r15,r1
SPR_ATTRR 30,r2,r3
SPR_STYLER 29,r4,r5
"""
        self.assertEqual(assemble(source, words=None), [
            0x40F00000, 0x41120000, 0x42340F80, 0x43560000,
            0x44780000, 0x459AB000, 0x46CDE000, 0x47F10000,
            0x48230F00, 0x49450E80])

    def test_legacy_golden_encodings_and_aliases(self):
        source = """
CLEAR_SCREEN
SET_PALETTE 255,0xF800
WRITE_TILEMAP 2,3,5
SET_SCROLL 8,4
UPDATE_BIRD_Y 100
DRAW_TRI_V1 10,10
DRAW_TRI_V2 20,10
DRAW_TRI_V3 10,20,255
SET_SPRITE_POS 1,40,60
SET_SPRITE_ATTR 1,1,1,0,0
SET_SPRITE_STYLE 1,3,1,3
BUFFER_CONFIG 1
BUFFER_SWAP
HALT
"""
        self.assertEqual(assemble(source, words=None), [
            0x0F000000, 0x10FFF800, 0x30020305, 0x50000804,
            0x60000064, 0x70000A0A, 0x8000140A, 0x9FF00A14,
            0xA08A0F00, 0xB080C000, 0xC0F30000, 0xD0000001,
            0xD1000000, HALT])
        self.assertEqual(assemble("SET_SCROLLR r1,r2", words=None), [0x41120000])

    def test_flow_golden_encodings(self):
        source = "NOP\nWAIT_FRAME\nSTATUS r15\nJMP 0\nJZ 255\nJNZ 0x7f\nHALT"
        self.assertEqual(assemble(source, words=None), [
            0xE0000000, 0xE1000000, 0xE5F00000, 0xE2000000,
            0xE30000FF, 0xE400007F, HALT])

    def test_labels_account_for_rectangle_expansion(self):
        source = """
JMP after
start: NOP
RECT 1,2,3,4,5
after: JZ start
JNZ AFTER
HALT
"""
        image = assemble(source, words=None)
        self.assertEqual(len(image), 11)
        self.assertEqual(image[0], 0xE2000008)
        self.assertEqual(image[2:8], [0x70000102, 0x80000302, 0x90500304,
                                          0x70000102, 0x80000304, 0x90500104])
        self.assertEqual(image[8:10], [0xE3000001, 0xE4000008])

    def test_register_rectangle_preserves_source_register_fields(self):
        self.assertEqual(assemble("RECTR r1,r2,r3,r4,r5", words=None), [
            0x43120000, 0x44320000, 0x45345000,
            0x43120000, 0x44340000, 0x45145000])
        image = assemble("JMP after\nRECTR r1,r2,r3,r4,r5\nafter: HALT", words=None)
        self.assertEqual(len(image), 8)
        self.assertEqual(image[0], 0xE2000007)

    def test_case_comments_decimal_hex_and_signed_operands(self):
        source = """
; ignored
Label: mOvI R01, +0X0010 # hex
addi r2 r01 -0x10 // negative signed immediate
jnz label
.word 4026531840
"""
        self.assertEqual(assemble(source, words=None), [
            0x20100010, 0x2A21FFF0, 0xE4000000, HALT])

    def test_padding_is_exact_halt(self):
        image = assemble("NOP\nHALT")
        self.assertEqual(len(image), 256)
        self.assertEqual(image[0], 0xE0000000)
        self.assertTrue(all(word == HALT for word in image[1:]))
        self.assertEqual(assemble("", words=2), [HALT, HALT])
        self.assertEqual(len(assemble("NOP\n" * 255 + "HALT")), 256)

    def test_invalid_inputs_report_source_line(self):
        cases = [
            ("MOVI r16,0", "invalid register"),
            ("MOV r1,ra", "invalid register"),
            ("MOVI r1,65536", "outside range"),
            ("MOVI r1,-1", "outside range"),
            ("ADDI r1,r2,32768", "outside range"),
            ("ADDI r1,r2,-32769", "outside range"),
            ("SPR_POS 32,0,0", "outside range"),
            ("SPR_POS 0,512,0", "outside range"),
            ("SPR_ATTR 0,0,2,0,0", "outside range"),
            ("SPR_STYLE 0,4,0,0", "outside range"),
            ("TILE 40,0,0", "outside range"),
            ("TILE 0,30,0", "outside range"),
            ("PALETTE 0,65536", "outside range"),
            ("JMP 256", "outside range"),
            ("JMP missing", "undefined label"),
            ("JUMP 0", "unknown instruction"),
            ("CMP r1", "expects 2"),
            ("HALT r1", "expects 0"),
            ("RECT 3,0,2,4,1", "inclusive corners"),
            ("RECT 1,0,1,4,1", "positive area"),
            ("RECT 0,1,4,1,1", "positive area"),
            ("MOVI r1,,3", "missing operand"),
            ("MOVI r1,", "missing operand"),
            ("MOVI r1,1+2", "expected an integer"),
            (".WORD 0x100000000", "outside range"),
        ]
        for statement, message in cases:
            with self.subTest(statement=statement):
                with self.assertRaisesRegex(AssemblyError, f"line 2: .*{message}"):
                    assemble("; line1\n" + statement)

    def test_duplicate_labels_and_capacity(self):
        with self.assertRaisesRegex(AssemblyError, "line 2: duplicate label"):
            assemble("A: NOP\na: HALT")
        with self.assertRaisesRegex(AssemblyError, "line 257: .*256-word"):
            assemble("NOP\n" * 257)
        with self.assertRaisesRegex(AssemblyError, "line 2: .*exceeds requested image size"):
            assemble("NOP\nHALT", words=1)
        for size in (0, -1, 257):
            with self.subTest(size=size):
                with self.assertRaisesRegex(AssemblyError, "image size"):
                    assemble("HALT", words=size)
        with self.assertRaisesRegex(AssemblyError, "line 1: .*outside address range"):
            assemble("JMP end\n" + "NOP\n" * 255 + "end:")

    def test_demo_images_match_sources_and_fit_fixed_rom(self):
        expected_sizes = {"background_sprites": 55, "polygons_motion": 44}
        for stem, expected_size in expected_sizes.items():
            with self.subTest(program=stem):
                source = (ROOT / "programs" / f"{stem}.asm").read_text()
                raw = assemble(source, words=None)
                stored = (ROOT / "programs" / f"{stem}.hex").read_text().splitlines()
                self.assertEqual(len(raw), expected_size)
                self.assertEqual(raw[-1], HALT)
                self.assertEqual(stored, [f"{word:08X}" for word in assemble(source)])
                self.assertEqual(len(stored), 256)
                self.assertTrue(all(word == "F0000000" for word in stored[expected_size:]))

    def test_cli_success_failure_and_no_host_code_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            source, output = temporary / "input.asm", temporary / "output.hex"
            source.write_text("MOVI r1,42\nHALT\n")
            result = subprocess.run([sys.executable, str(ROOT / "tools" / "assemble.py"),
                                     str(source), "-o", str(output), "--words", "4"],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(), "2010002A\nF0000000\nF0000000\nF0000000\n")
            source.write_text("; heading\nMOVI r1,__import__('os').system('false')\n")
            result = subprocess.run([sys.executable, str(ROOT / "tools" / "assemble.py"),
                                     str(source), "-o", str(output)],
                                    capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("line 2", result.stderr)
            self.assertIn("expected an integer", result.stderr)
            self.assertEqual(output.read_text(), "2010002A\nF0000000\nF0000000\nF0000000\n")
            result = subprocess.run([sys.executable, str(ROOT / "tools" / "assemble.py"),
                                     str(source), "-o", str(source)],
                                    capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("output path must differ", result.stderr)
            self.assertIn("__import__", source.read_text())
            alias = temporary / "same-file.hex"
            alias.symlink_to(source)
            result = subprocess.run([sys.executable, str(ROOT / "tools" / "assemble.py"),
                                     str(source), "-o", str(alias)],
                                    capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("output path must differ", result.stderr)
            self.assertIn("__import__", source.read_text())


if __name__ == "__main__":
    unittest.main()
