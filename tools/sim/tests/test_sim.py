"""Tests for the headless simulator (D-011). Run: python -m unittest discover -s tools/sim/tests"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import sim  # noqa: E402

FIXTURES = Path(__file__).with_name("fixtures")


def fake_client(**kwargs):
    kwargs.setdefault("addons", ["FakeAddon"])
    return sim.Client(addons_root=FIXTURES, **kwargs)


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.client = fake_client()
        self.addCleanup(self.client.close)

    def test_files_load_in_toc_order_with_shared_namespace(self):
        self.client.login()
        self.assertEqual(self.client.chat, ["loaded truetrue"])  # backslash path normalised
        self.assertEqual(self.client.errors, [])

    def test_lifecycle_events_fire_in_client_order(self):
        self.client.login()
        self.client.logout()
        self.assertEqual(self.client.get("FakeDB.events"), ["ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT"])

    def test_saved_variables_round_trip_across_reload(self):
        self.client.login()
        self.client.reload()
        self.assertEqual(self.client.get("FakeDB.loads"), 2)
        self.assertEqual(self.client.get("FakeCharDB.visits"), 2)
        self.assertEqual(
            self.client.get("FakeDB.events"),
            ["ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "ADDON_LOADED", "PLAYER_LOGIN"],
        )

    def test_saved_variables_are_written_per_scope(self):
        self.client.login()
        self.client.logout()
        self.assertIn("FakeDB", (self.client.sv_dir / "account" / "FakeAddon.lua").read_text())
        self.assertIn("FakeCharDB", (self.client.sv_dir / "Testrealm-Testwarrior" / "FakeAddon.lua").read_text())

    def test_a_later_session_sees_saved_variables_from_disk(self):
        self.client.login()
        self.client.logout()
        second = fake_client(sv_dir=self.client.sv_dir)
        second.login()
        self.assertEqual(second.get("FakeDB.loads"), 2)

    def test_slash_command_dispatch(self):
        self.client.login()
        self.assertTrue(self.client.slash("/FAKE hello world"))
        self.assertEqual(self.client.chat[-1], "fake:hello world")
        self.assertFalse(self.client.slash("/nothing"))

    def test_handler_error_is_captured_and_does_not_stop_other_handlers(self):
        self.client.login()
        self.client.set_combat(True)
        self.assertEqual(len(self.client.errors), 1)
        self.assertIn("boom", self.client.errors[0])
        self.client.fire("PLAYER_LOGOUT")
        self.assertIn("PLAYER_LOGOUT", self.client.get("FakeDB.events"))

    def test_timers_follow_the_simulated_clock_and_debounce(self):
        self.client.login()
        for _ in range(3):
            self.client.fire("BAG_UPDATE_DELAYED")
        self.client.advance(0.4)
        self.assertEqual(self.client.get("FakeDB.bagScans"), 0)
        self.client.advance(0.2)
        self.assertEqual(self.client.get("FakeDB.bagScans"), 1)

    def test_registered_events_are_recorded(self):
        self.client.login()
        self.assertIn("BAG_UPDATE_DELAYED", self.client.registered_events())

    def test_rejected_event_registration_raises_like_the_client(self):
        client = fake_client(scenario={"rejectEvents": {"MADE_UP_EVENT": True}})
        self.addCleanup(client.close)
        client.login()
        template = "(function() local f = CreateFrame('Frame'); return (pcall(f.RegisterEvent, f, '%s')) end)()"
        self.assertFalse(client.eval(template % "MADE_UP_EVENT"))
        self.assertTrue(client.eval(template % "OK_EVENT"))

    def test_unknown_frame_methods_are_stubs_and_unknown_fields_are_nil(self):
        self.client.login()
        self.assertIsNone(self.client.eval("CreateFrame('Frame').notAField"))
        self.client.eval("(function() CreateFrame('Frame'):SetSomethingNew() end)()")
        self.assertIn("SetSomethingNew", self.client.stubbed_methods())

    def test_wow_string_helpers(self):
        self.client.login()
        self.assertEqual(self.client.eval("strtrim('  hi  ')"), "hi")
        self.assertEqual(self.client.eval("strjoin(',', 'a', 1, true)"), "a,1,true")
        self.assertEqual(self.client.eval("select('#', strsplit(' ', 'a b c'))"), 3)
        self.assertEqual(self.client.eval("select(2, strsplit(' ', 'a b c', 2))"), "b c")

    def test_runtime_is_lua_51_without_later_features(self):
        self.client.login()
        self.assertEqual(self.client.eval("_VERSION"), "Lua 5.1")
        self.assertIsNone(self.client.eval("utf8"))


class LoadFailureTests(unittest.TestCase):
    def test_runtime_error_stops_that_addon_and_is_reported(self):
        client = sim.Client(addons=["ErrorAddon"], addons_root=FIXTURES)
        self.addCleanup(client.close)
        client.login()
        self.assertTrue(any("load boom" in e for e in client.errors))
        self.assertIsNone(client.get("AfterRan"))

    def test_toc_listing_a_missing_file_is_a_setup_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "Broken"
            folder.mkdir()
            (folder / "Broken.toc").write_text("## Interface: 120105\nmissing.lua\n")
            client = sim.Client(addons=["Broken"], addons_root=Path(tmp))
            self.addCleanup(client.close)
            with self.assertRaises(sim.SimError):
                client.login()

    def test_out_of_date_interface_is_a_warning_not_a_failure(self):
        client = fake_client(scenario={"build": {"interface": 130000}})
        self.addCleanup(client.close)
        client.login()
        self.assertTrue(any("out of date" in w for w in client.warnings))
        self.assertEqual(client.get("FakeDB.loads"), 1)


class DataApiTests(unittest.TestCase):
    def setUp(self):
        self.client = fake_client(scenario="miner")
        self.addCleanup(self.client.close)
        self.client.login()

    def test_container_api_reflects_scenario_and_is_flagged_assumed(self):
        self.assertEqual(self.client.eval("C_Container.GetContainerNumSlots(0)"), 16)
        self.assertEqual(self.client.eval("C_Container.GetContainerItemInfo(0, 1).stackCount"), 18)
        self.assertIsNone(self.client.eval("C_Container.GetContainerItemInfo(0, 9)"))
        self.assertIn("C_Container.GetContainerItemInfo", self.client.assumed_apis_used())

    def test_known_apis_are_not_flagged(self):
        self.client.eval("GetBuildInfo()")
        self.assertEqual(self.client.assumed_apis_used(), [])

    def test_world_can_be_changed_while_running(self):
        self.client.set("money", 5000)
        self.assertEqual(self.client.eval("GetMoney()"), 5000)
        self.client.set("bags.0.slots", 20)
        self.assertEqual(self.client.eval("C_Container.GetContainerNumSlots(0)"), 20)

    def test_combat_state_and_events(self):
        self.client.set_combat(True)
        self.assertTrue(self.client.eval("InCombatLockdown()"))

    def test_item_hyperlinks_are_stripped_for_plain_text_comparison(self):
        link = self.client.eval("C_Container.GetContainerItemInfo(0, 1).hyperlink")
        self.assertEqual(sim.strip_codes(link), "[Test Copper Ore]")


class WarriorWorkshopTests(unittest.TestCase):
    """The real add-on, loaded as the client would. Add checks here as milestones land."""

    def setUp(self):
        self.client = sim.Client(scenario="fresh")
        self.addCleanup(self.client.close)
        self.client.login()

    def test_loads_without_errors(self):
        self.assertEqual(self.client.errors, [])

    def test_version_command(self):
        self.client.slash("/ww version")
        self.assertRegex(
            self.client.chat[-1],
            r"^Warrior Workshop: Warrior Workshop \d+\.\d+\.\d+ - schema \S+ - interface 120105 \(build \d+\)$",
        )

    def test_unknown_subcommand_is_handled(self):
        self.client.slash("/ww definitely-not-a-command")
        self.assertEqual(self.client.errors, [])
        self.assertTrue(self.client.chat)

    def test_survives_reload(self):
        self.client.reload()
        self.assertEqual(self.client.errors, [])

    def test_login_reports_no_unavailable_core_apis(self):
        # Context and SpellMap (M2) query zone, group, death and encounter state at login.
        self.assertFalse([line for line in self.client.chat if "API unavailable" in line], self.client.chat)

    def test_context_follows_combat_with_debug_on(self):
        self.client.slash("/ww debug")
        self.client.clear_chat()
        self.client.set_combat(True)
        self.client.set_combat(False)
        lines = [line for line in self.client.chat if "[debug] context:" in line]
        self.assertEqual(len(lines), 2, self.client.chat)
        self.assertIn("combat=true", lines[0])
        self.assertIn("combat=false", lines[1])
        self.assertEqual(self.client.errors, [])

    def test_assumed_apis_used_are_visible(self):
        # Informational guard: if this list grows, the checks above rest on unverified fakes.
        self.assertIsInstance(self.client.assumed_apis_used(), list)


if __name__ == "__main__":
    unittest.main()
