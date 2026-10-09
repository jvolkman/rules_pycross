import sys
import unittest
from pathlib import Path


class TestZstandardMuslWheel(unittest.TestCase):
    def test_wheel_is_musllinux(self):
        wheels = [w.name for d in sys.argv[1:] for w in Path(d).glob("*.whl")]
        self.assertEqual(len(wheels), 1, wheels)
        self.assertRegex(wheels[0], r"^zstandard-.*-cp314-cp314-musllinux_1_2_x86_64\.whl$")


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1])
