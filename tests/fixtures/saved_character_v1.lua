-- A character database saved by schema v1 (M2 before SPEC_V2), with edited weights and some Workshop data.
return {
    schemaVersion = 1,
    meta = { name = "Hugh", realm = "Realm", classFile = "WARRIOR", level = 12, lastSeen = 1728400000 },
    inventory = { bags = { [2589] = 20 }, bank = {} },
    targets = { example = { name = "Copper Chain Belt", note = "learn at 35" } },
    gear = {
        activeProfile = "tank",
        profiles = {
            dps = { label = "DPS", weights = { str = 1.5 } },
            tank = { label = "Tank", weights = { sta = 2.0 } },
        },
    },
    readiness = { durabilityAmber = 0.5 },
}
