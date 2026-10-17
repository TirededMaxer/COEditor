"""Release cleanup must never run before asset and publication verification."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("publish", Path(__file__).resolve().parents[1] / "scripts/publish-release.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class RemoteAssetTests(unittest.TestCase):
    def test_partial_upload_is_rejected_before_download(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "app.dmg").write_bytes(b"app")
            asset = {"name": "app.dmg", "state": "new", "size": 0, "digest": None, "id": 1}
            with patch.object(publisher, "gh") as gh:
                with self.assertRaises(RuntimeError):
                    publisher.verify_assets("owner/repo", {"assets": [asset]}, directory, ["app.dmg"])
                gh.assert_not_called()

    def test_download_must_match_even_when_metadata_matches(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "app.dmg").write_bytes(b"app")
            asset = {"name": "app.dmg", "state": "uploaded", "size": 3, "digest": "sha256:" + hashlib.sha256(b"app").hexdigest(), "id": 1}
            with patch.object(publisher, "gh", return_value=b"bad"):
                with self.assertRaises(RuntimeError):
                    publisher.verify_assets("owner/repo", {"assets": [asset]}, directory, ["app.dmg"])


if __name__ == "__main__":
    unittest.main()
