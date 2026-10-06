"""The importer's catalog and cleanup safety, with throwaway folders only.

    /usr/bin/python3 -m unittest scripts/test_wallpaper_library.py
"""
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import wallpaper_library as importer  # noqa: E402


class CatalogSafetyTests(unittest.TestCase):
    def setUp(self):
        self.library = tempfile.mkdtemp(prefix="allset-import-test-")
        self.root = tempfile.mkdtemp(prefix="allset-import-root-")

    def tearDown(self):
        shutil.rmtree(self.library, ignore_errors=True)
        shutil.rmtree(self.root, ignore_errors=True)

    def asset(self, relative, content="x"):
        path = os.path.join(self.library, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(content)
        return path

    def exists(self, relative):
        return os.path.exists(os.path.join(self.library, relative))

    def test_a_missing_catalog_is_a_fresh_library(self):
        self.assertEqual(importer.load_catalog(self.library)["items"], [])

    def test_an_unreadable_catalog_is_kept_and_stops_the_import(self):
        """Review R9: it was treated as empty, then cleanup deleted another root's files."""
        with open(os.path.join(self.library, "catalog.json"), "w") as handle:
            handle.write("{ damaged")
        self.asset("live/otherroot.mp4", "someone else's")
        original_inventory = importer.inventory
        importer.inventory = lambda root, library: {"root": self.root, "files": []}
        try:
            with self.assertRaises(importer.CatalogUnreadable):
                importer.import_library(self.root, self.library, live=False)
        finally:
            importer.inventory = original_inventory
        self.assertTrue(self.exists("live/otherroot.mp4"))
        with open(os.path.join(self.library, "catalog.json")) as handle:
            self.assertEqual(handle.read(), "{ damaged")
        copies = [n for n in os.listdir(self.library) if n.startswith("catalog.unreadable-")]
        self.assertEqual(len(copies), 1)

    def test_a_catalog_of_the_wrong_shape_counts_as_unreadable(self):
        with open(os.path.join(self.library, "catalog.json"), "w") as handle:
            json.dump([1, 2], handle)
        with self.assertRaises(importer.CatalogUnreadable):
            importer.load_catalog(self.library)

    def test_orphans_are_moved_aside_not_deleted(self):
        self.asset("live/used.mp4")
        self.asset("live/orphan.mp4", "keep me recoverable")
        importer.clean_orphans(self.library, {"items": [{"id": "used", "playback": "live/used.mp4"}]})
        self.assertTrue(self.exists("live/used.mp4"))
        self.assertFalse(self.exists("live/orphan.mp4"))
        held = [os.path.join(base, name) for base, _, names in os.walk(os.path.join(self.library, ".orphans")) for name in names]
        self.assertEqual(len(held), 1)
        with open(held[0]) as handle:
            self.assertEqual(handle.read(), "keep me recoverable")

    def test_an_empty_catalog_never_clears_the_library(self):
        self.asset("live/a.mp4")
        self.asset("thumbnails/a.jpg")
        importer.clean_orphans(self.library, {"items": []})
        self.assertTrue(self.exists("live/a.mp4"))
        self.assertTrue(self.exists("thumbnails/a.jpg"))

    def test_only_the_latest_few_cleanups_are_kept(self):
        for run in range(5):
            self.asset(f"live/orphan{run}.mp4")
            self.asset("live/used.mp4")
            importer.clean_orphans(self.library, {"items": [{"playback": "live/used.mp4"}]}, stamp=f"2026100{run}-000000")
        runs = sorted(os.listdir(os.path.join(self.library, ".orphans")))
        self.assertEqual(runs, ["20261002-000000", "20261003-000000", "20261004-000000"])


if __name__ == "__main__":
    unittest.main()
