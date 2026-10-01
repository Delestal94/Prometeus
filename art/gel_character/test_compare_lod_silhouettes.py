"""S-311 B: pixel comparison rejects incomplete, mismatched and blank captures."""

import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

from compare_lod_silhouettes import compare


class SilhouetteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        image = Image.new("RGB", (1920, 1080))
        image.paste("white", (950, 500, 970, 600))
        image.save(self.directory / "body.png")
        Image.new("RGB", (1920, 1080)).save(self.directory / "blank.png")
        self.manifest = {"resolution": [1920, 1080], "distance_m": 15.0, "fov_vertical_deg": 60.0,
                         "captures": [{"lod": lod, "state": f"state{state}", "view": view,
                                       "weights": {}, "file": "body.png"}
                                      for lod in range(3) for state in range(24)
                                      for view in ("front", "profile", "three_quarter")]}

    def tearDown(self):
        self.temp.cleanup()

    def write(self):
        (self.directory / "capture_manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def test_identical_passes_but_does_not_certify_full_flaca(self):
        self.write()
        result = compare(self.directory)
        self.assertTrue(result["passed_diagnostic_samples"])
        self.assertFalse(result["final_item_17_complete"])
        self.assertEqual(result["worst_pixel_difference"], 0)

    def test_incomplete_rejected(self):
        self.manifest["captures"].pop()
        self.write()
        with self.assertRaisesRegex(ValueError, "all three"):
            compare(self.directory)

    def test_blank_rejected(self):
        for row in self.manifest["captures"]:
            row["file"] = "blank.png"
        self.write()
        with self.assertRaisesRegex(ValueError, "Empty"):
            compare(self.directory)

    def test_weights_mismatch_rejected(self):
        self.manifest["captures"][72]["weights"] = {"belly": 1}
        self.write()
        with self.assertRaisesRegex(ValueError, "different morph"):
            compare(self.directory)


if __name__ == "__main__":
    unittest.main()
