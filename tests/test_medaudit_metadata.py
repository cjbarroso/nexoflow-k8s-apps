import shutil
import tempfile
import unittest
from pathlib import Path

from scripts.validate_medaudit_metadata import validate


ROOT = Path(__file__).resolve().parents[1]


class MedAuditMetadataTest(unittest.TestCase):
    def test_repository_metadata_is_current(self):
        self.assertEqual(validate(ROOT), [])

    def test_stale_declared_sha_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            copy = Path(temporary)
            shutil.copytree(ROOT / "src", copy / "src")
            manifest = copy / "src/hhccia-v2/hhccia-core.yaml"
            text = manifest.read_text()
            manifest.write_text(text.replace(
                'value: "7f3479c4449533f7f2249febd817ff3b445ade32"',
                'value: "0000000000000000000000000000000000000000"',
                1,
            ))
            errors = validate(copy)
            self.assertTrue(any("FRONT_BUILD_SHA" in error for error in errors))

    def test_stale_production_adapter_declared_sha_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            copy = Path(temporary)
            shutil.copytree(ROOT / "src", copy / "src")
            manifest = copy / "src/hhccia-v2/hhccia-core.yaml"
            text = manifest.read_text()
            manifest.write_text(text.replace(
                'value: "18a2116e74d98c71b3d5e07f34bb82d2d635fb74"',
                'value: "0000000000000000000000000000000000000000"',
                1,
            ))
            errors = validate(copy)
            self.assertTrue(any("ADAPTER_BUILD_SHA" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
