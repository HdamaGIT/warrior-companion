"""Tests for tools/wowdev.py. Junction tests run on Windows only; the rest run anywhere (CI is Linux)."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import wowdev  # noqa: E402


class WowDevTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.client = self.root / "_classic_beta_"
        (self.client / "Interface" / "AddOns").mkdir(parents=True)

    def test_read_version_matches_the_client_product(self):
        (self.client / ".flavor.info").write_text("Product Flavor!STRING:0\nwow_classic_beta\n", encoding="utf-8")
        (self.root / ".build.info").write_text(
            "Branch!STRING:0|Version!STRING:0|Product!STRING:0\n"
            "eu|2.5.6.1|wow_anniversary\n"
            "us|1.60.1.70291|wow_classic_beta\n",
            encoding="utf-8",
        )
        self.assertEqual(wowdev.read_version(self.root, self.client), "wow_classic_beta 1.60.1.70291")

    def test_read_version_tolerates_missing_files(self):
        self.assertIsNone(wowdev.read_version(self.root, self.client))

    def test_saved_files_finds_account_and_character_files_only(self):
        account = self.client / "WTF" / "Account" / "123#1"
        wanted = [
            account / "SavedVariables" / "WarriorWorkshop.lua",
            account / "SavedVariables" / "WarriorWorkshopProbe.lua",
            account / "Realm" / "Hugh" / "SavedVariables" / "WarriorWorkshop.lua",
        ]
        ignored = [account / "SavedVariables" / "Blizzard_CombatLog.lua", account / "WarriorWorkshop.lua"]
        for path in wanted + ignored:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("x", encoding="utf-8")
        self.assertEqual(wowdev.saved_files(self.client), sorted(wanted))

    @unittest.skipUnless(sys.platform == "win32", "junctions are Windows-only")
    def test_removing_a_junction_keeps_the_target(self):
        target = self.root / "repo_addon"
        target.mkdir()
        (target / "keep.lua").write_text("-- must survive", encoding="utf-8")
        link = self.client / "Interface" / "AddOns" / "repo_addon"
        wowdev.make_junction(link, target)
        self.assertTrue(wowdev.is_link(link))
        wowdev.remove_install(link)
        self.assertFalse(link.exists())
        self.assertTrue((target / "keep.lua").exists())


if __name__ == "__main__":
    unittest.main()
