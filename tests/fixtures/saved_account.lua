-- An account database as saved by a user who has changed some settings and entered a price.
return {
    schemaVersion = 1,
    settings = {
        debug = true,
        batchSize = 9,
        window = { point = "TOPLEFT", x = 10, y = -20 },
    },
    prices = {
        [12345] = { value = 1500, source = "manual", updatedAt = 1728400000 },
    },
}
