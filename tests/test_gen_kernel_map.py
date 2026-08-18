"""Offline unit tests for .github/scripts/gen-kernel-map.py.

The script's fetch function is injectable, so every test runs without
network access.
"""
import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / ".github" / "scripts" / "gen-kernel-map.py"
spec = importlib.util.spec_from_file_location("gen_kernel_map", SCRIPT)
gkm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gkm)

LISTING = """
<a href="25.10.0/?wrap=1">25.10.0</a>
<a href="./25.10.1/">25.10.1</a>
<a href="25.10.4.1/">25.10.4.1</a>
<a href="latest/">latest</a>
<a href="incoming/">incoming</a>
"""
MTREE = (
    "./usr/lib/modules/6.12.33-production+truenas/kernel type=dir\n"
    "./usr/lib/modules type=dir\n"
)


class ListVersions(unittest.TestCase):
    def test_parses_version_dirs_only(self):
        got = gkm.list_versions("Goldeye", fetch=lambda url: LISTING)
        self.assertEqual(got, ["25.10.0", "25.10.1", "25.10.4.1"])


class ResolveKernel(unittest.TestCase):
    def test_extracts_kernel(self):
        got = gkm.resolve_kernel("Goldeye", "25.10.0", fetch=lambda url: MTREE)
        self.assertEqual(got, "6.12.33-production+truenas")

    def test_fetch_failure_returns_none(self):
        def boom(url):
            raise OSError("HTTP 404")
        self.assertIsNone(gkm.resolve_kernel("Goldeye", "25.10.4.1", fetch=boom))

    def test_no_kernel_path_returns_none(self):
        self.assertIsNone(gkm.resolve_kernel("Goldeye", "25.10.0",
                                             fetch=lambda url: "no modules here"))


class UpdateMap(unittest.TestCase):
    def setUp(self):
        self.calls = []

    def fake_fetch(self, url):
        self.calls.append(url)
        if url.endswith("/"):
            return LISTING
        if "25.10.4.1" in url:
            raise OSError("HTTP 404")
        return MTREE

    def test_fills_map_and_tracks_unresolved(self):
        data = gkm.update_map({}, fetch=self.fake_fetch)
        for train in gkm.TRAINS:
            self.assertEqual(data["trains"][train]["25.10.0"],
                             "6.12.33-production+truenas")
            self.assertEqual(data["trains"][train]["25.10.1"],
                             "6.12.33-production+truenas")
            self.assertNotIn("25.10.4.1", data["trains"][train])
            self.assertIn("25.10.4.1", data["unresolved"][train])

    def test_cached_versions_not_refetched(self):
        cached = {"25.10.0": "k", "25.10.1": "k", "25.10.4.1": "k"}
        data = {"trains": {t: dict(cached) for t in gkm.TRAINS}, "unresolved": {}}
        gkm.update_map(data, fetch=self.fake_fetch)
        self.assertTrue(all(u.endswith("/") for u in self.calls),
                        f"mtree fetched for a cached version: {self.calls}")

    def test_unresolved_cleared_when_mtree_appears(self):
        data = {"trains": {t: {} for t in gkm.TRAINS},
                "unresolved": {t: ["25.10.0"] for t in gkm.TRAINS}}
        gkm.update_map(data, fetch=lambda url: LISTING if url.endswith("/") else MTREE)
        self.assertEqual(data["unresolved"], {})

    def test_listing_failure_keeps_cached_data(self):
        def broken(url):
            raise OSError("connection refused")
        data = {"trains": {t: {"25.10.0": "cached-kernel"} for t in gkm.TRAINS},
                "unresolved": {}}
        gkm.update_map(data, fetch=broken)
        for train in gkm.TRAINS:
            self.assertEqual(data["trains"][train]["25.10.0"], "cached-kernel")


if __name__ == "__main__":
    unittest.main()
