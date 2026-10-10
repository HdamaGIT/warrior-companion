"""Tests for the visual preview (tools/sim/preview.py)."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import preview  # noqa: E402
import sim  # noqa: E402

FIXTURES = Path(__file__).with_name("fixtures")


def frame(id_, **kw):
    base = {"id": id_, "type": "Frame", "visible": True, "shown": True, "points": []}
    base.update(kw)
    return base


def point(p, rel=None, rp=None, x=0, y=0):
    return {"point": p, "relativeTo": rel, "relativePoint": rp or p, "x": x, "y": y}


class AnchorTests(unittest.TestCase):
    def layout(self, *frames):
        return preview.Layout([frame(1, name="UIParent"), *frames], (1000, 500))

    def test_single_anchor_uses_size(self):
        lay = self.layout(frame(2, parent=1, width=100, height=50, points=[point("CENTER")]))
        r = lay.rect(2)
        self.assertEqual((r.left, r.bottom, r.width, r.height), (450, 225, 100, 50))

    def test_offsets_are_y_up(self):
        lay = self.layout(frame(2, parent=1, width=10, height=10, points=[point("TOPLEFT", x=5, y=-20)]))
        r = lay.rect(2)
        self.assertEqual((r.left, r.top), (5, 480))

    def test_two_anchors_stretch_and_override_size(self):
        lay = self.layout(frame(2, parent=1, width=999, height=999,
                                points=[point("TOPLEFT", x=10, y=-10), point("BOTTOMRIGHT", x=-10, y=10)]))
        r = lay.rect(2)
        self.assertEqual((r.left, r.bottom, r.width, r.height), (10, 10, 980, 480))

    def test_anchor_to_sibling(self):
        lay = self.layout(
            frame(2, parent=1, width=100, height=100, points=[point("BOTTOMLEFT")]),
            frame(3, parent=1, width=20, height=20, points=[point("LEFT", rel=2, rp="RIGHT", x=5)]),
        )
        r = lay.rect(3)
        self.assertEqual((r.left, r.bottom), (105, 40))

    def test_anchor_loop_is_a_warning_not_a_crash(self):
        lay = self.layout(
            frame(2, parent=1, width=10, height=10, points=[point("LEFT", rel=3)]),
            frame(3, parent=1, width=10, height=10, points=[point("LEFT", rel=2)]),
        )
        lay.rect(2)
        self.assertTrue(any("anchor loop" in w for w in lay.warnings))

    def test_colour_codes_become_spans(self):
        out = preview.wow_text_to_html("a |cffff0000red|r <b>", "white")
        self.assertIn('<span style="color:#ff0000">red</span>', out)
        self.assertIn("&lt;b&gt;", out)


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.client = sim.Client(addons=["UiAddon"], addons_root=FIXTURES)
        self.addCleanup(self.client.close)
        self.client.login()
        self.out = Path(tempfile.mkdtemp())

    def test_set_point_forms_are_recorded(self):
        frames = {f.get("name"): f for f in self.client.frames()}
        hud = frames["UiAddonHUD"]
        self.assertEqual(hud["points"][0]["point"], "CENTER")
        self.assertEqual((hud["width"], hud["height"]), (240, 80))

    def test_get_point_round_trips_set_point(self):
        point = self.client.eval("(function() return {UiAddonHUD:GetPoint(1)} end)()")
        self.assertEqual(point[0], "CENTER")
        self.assertEqual(point[2:], ["CENTER", 0, -200])
        self.assertEqual(self.client.eval("UiAddonHUD:GetPoint(1) and select(2, UiAddonHUD:GetPoint(1)) == UIParent"), True)
        self.assertIsNone(self.client.eval("UiAddonHUD:GetPoint(5)"))

    def test_snapshot_draws_visible_text_and_flags_templates(self):
        path, warnings = self.client.snapshot(self.out / "hud.html")
        page = path.read_text(encoding="utf-8")
        self.assertIn("Warrior HUD", page)
        self.assertIn("color:#00ff00", page)
        self.assertTrue(any("UIPanelButtonTemplate" in w for w in warnings))
        self.assertEqual(self.client.templates_used(), ["UIPanelButtonTemplate"])

    def test_hidden_frames_follow_events(self):
        frames = {f.get("name"): f for f in self.client.frames()}
        self.assertFalse(frames["UiAddonSuspended"]["visible"])
        self.client.set_combat(True)
        frames = {f.get("name"): f for f in self.client.frames()}
        self.assertTrue(frames["UiAddonSuspended"]["visible"])

    def test_hud_position_matches_anchors(self):
        lay = preview.Layout(self.client.frames(), (1920, 1080))
        hud = next(f for f in self.client.frames() if f.get("name") == "UiAddonHUD")
        r = lay.rect(hud["id"])
        self.assertEqual((r.left, r.bottom), (840, 300))

    def test_unanchored_visible_text_is_warned(self):
        self.client.eval("(function() UiAddonHUD:CreateFontString():SetText('lost') end)()")
        _, warnings = self.client.snapshot(self.out / "x.html")
        self.assertTrue(any("no anchor" in w for w in warnings))

    def test_offscreen_frame_is_warned(self):
        self.client.eval("(function() UiAddonHUD:SetPoint('CENTER', UIParent, 'CENTER', 5000, 0) end)()")
        _, warnings = self.client.snapshot(self.out / "x.html")
        self.assertTrue(any("off-screen" in w for w in warnings))

    def test_cli_snapshot_directive(self):
        target = self.out / "cli"
        sim.SNAPSHOT_DIR, saved = target, sim.SNAPSHOT_DIR
        try:
            sim.dispatch(self.client, "!snapshot demo")
        finally:
            sim.SNAPSHOT_DIR = saved
        self.assertTrue((target / "demo.html").exists())


if __name__ == "__main__":
    unittest.main()
