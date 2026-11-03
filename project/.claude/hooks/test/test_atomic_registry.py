"""Regression tests for registry writes when a disk fills mid-write."""

import errno
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from registry_lock import atomic_write_json


class AtomicRegistryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = os.path.join(self.temp.name, "registry.json")

    def test_writes_complete_json(self):
        data = {"issues": [{"id": "ISS-001", "title": "한글"}]}
        atomic_write_json(self.path, data)
        with open(self.path, encoding="utf-8") as stream:
            self.assertEqual(json.load(stream), data)

    def test_enospc_preserves_original(self):
        original = {"issues": [{"id": "ISS-001"}]}
        atomic_write_json(self.path, original)
        before = Path(self.path).read_bytes()

        def fail_after_partial_write(data, stream, **kwargs):
            stream.write('{"issues":')
            raise OSError(errno.ENOSPC, "No space left on device")

        with patch("registry_lock.json.dump", side_effect=fail_after_partial_write):
            with self.assertRaises(OSError) as error:
                atomic_write_json(self.path, {"issues": [{"id": "ISS-002"}]})
        self.assertEqual(error.exception.errno, errno.ENOSPC)
        self.assertEqual(Path(self.path).read_bytes(), before)
        self.assertEqual(list(Path(self.temp.name).iterdir()), [Path(self.path)])

    def test_rejects_empty_data(self):
        atomic_write_json(self.path, {"issues": []})
        before = Path(self.path).read_bytes()
        for data in (None, {}):
            with self.subTest(data=data), self.assertRaises(ValueError):
                atomic_write_json(self.path, data)
            self.assertEqual(Path(self.path).read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
