import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "generate_picture_manifest.py"
SPEC = importlib.util.spec_from_file_location("picture_manifest", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class GeneratePictureManifestTest(unittest.TestCase):
    def test_indexes_nested_pngs_preserving_paths_and_sizes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "words").mkdir()
            (root / "words" / " Apple .PNG").write_bytes(b"image")
            (root / "book.png").write_bytes(b"book")
            (root / "ignored.jpg").write_bytes(b"ignored")
            (root / ".hidden").mkdir()
            (root / ".hidden" / "secret.png").write_bytes(b"hidden")
            (root / ".secret.png").write_bytes(b"hidden")
            self.assertEqual(MODULE.generate_manifest(root), {
                "version": 1,
                "images": {
                    "apple": {"path": "words/ Apple .PNG", "bytes": 5},
                    "book": {"path": "book.png", "bytes": 4},
                },
            })

    def test_rejects_normalized_collisions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "nested").mkdir()
            (root / "Apple.png").write_bytes(b"a")
            (root / "nested" / " apple .png").write_bytes(b"b")
            with self.assertRaisesRegex(ValueError, "collision.*apple"):
                MODULE.generate_manifest(root)

    def test_cli_output_is_deterministic(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "zebra.png").write_bytes(b"z")
            (root / "ant.png").write_bytes(b"a")
            command = [sys.executable, str(SCRIPT), str(root)]
            subprocess.run(command, check=True, capture_output=True)
            first = (root / "manifest.json").read_bytes()
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(first, (root / "manifest.json").read_bytes())
            self.assertEqual(list(json.loads(first)["images"]), ["ant", "zebra"])

    def test_rejects_missing_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, "does not exist"):
                MODULE.generate_manifest(Path(temporary) / "missing")


if __name__ == "__main__":
    unittest.main()
