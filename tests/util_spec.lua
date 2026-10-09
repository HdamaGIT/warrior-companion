local H = dofile("tests/helpers/load_addon.lua")

describe("util", function()
    local Util

    before_each(function()
        Util = H.newNs({ "Locale/enUS.lua", "Core/Util.lua" }).Util
    end)

    describe("DeepCopy", function()
        it("copies nested tables independently", function()
            local source = { a = 1, nested = { b = 2, list = { 1, 2, 3 } } }
            local copy = Util.DeepCopy(source)
            assert.are.same(source, copy)
            copy.nested.list[1] = 99
            assert.are.equal(1, source.nested.list[1])
            assert.are_not.equal(source.nested, copy.nested)
        end)

        it("returns non-table values unchanged", function()
            assert.are.equal(5, Util.DeepCopy(5))
            assert.are.equal("x", Util.DeepCopy("x"))
            assert.is_nil(Util.DeepCopy(nil))
        end)

        it("preserves cycles", function()
            local source = { name = "loop" }
            source.self = source
            local copy = Util.DeepCopy(source)
            assert.are.equal(copy, copy.self)
            assert.are_not.equal(source, copy)
        end)
    end)

    describe("MergeDefaults", function()
        it("fills missing keys, including nested ones", function()
            local target = { a = 1, nested = { x = 1 } }
            Util.MergeDefaults(target, { a = 5, b = 2, nested = { x = 9, y = 8 } })
            assert.are.same({ a = 1, b = 2, nested = { x = 1, y = 8 } }, target)
        end)

        it("never overwrites user values, even false or of a different type", function()
            local target = { flag = false, count = "seven", box = "not a table" }
            Util.MergeDefaults(target, { flag = true, count = 7, box = { inner = 1 } })
            assert.are.same({ flag = false, count = "seven", box = "not a table" }, target)
        end)

        it("does not alias the defaults", function()
            local defaults = { nested = { list = { 1 } } }
            local target = Util.MergeDefaults({}, defaults)
            target.nested.list[1] = 42
            assert.are.equal(1, defaults.nested.list[1])
        end)

        it("returns the target", function()
            local target = {}
            assert.are.equal(target, Util.MergeDefaults(target, {}))
        end)
    end)

    describe("RingPush", function()
        it("appends while under the cap", function()
            local buffer = {}
            Util.RingPush(buffer, "a", 3)
            Util.RingPush(buffer, "b", 3)
            assert.are.same({ "a", "b" }, buffer)
        end)

        it("drops the oldest entries beyond the cap", function()
            local buffer = {}
            for value = 1, 5 do
                Util.RingPush(buffer, value, 3)
            end
            assert.are.same({ 3, 4, 5 }, buffer)
        end)

        it("trims an over-long buffer in one push", function()
            local buffer = { 1, 2, 3, 4, 5 }
            Util.RingPush(buffer, 6, 2)
            assert.are.same({ 5, 6 }, buffer)
        end)
    end)

    describe("Trim and Split", function()
        it("trims both ends", function()
            assert.are.equal("a b", Util.Trim("  a b \t"))
            assert.are.equal("", Util.Trim("   "))
        end)

        it("splits on a plain separator and keeps empty fields", function()
            assert.are.same({ "a", "b", "", "c" }, Util.Split("a,b,,c", ","))
        end)

        it("treats pattern characters literally and supports long separators", function()
            assert.are.same({ "a", "b" }, Util.Split("a.b", "."))
            assert.are.same({ "a", "b" }, Util.Split("a::b", "::"))
        end)

        it("returns the whole string when there is nothing to split on", function()
            assert.are.same({ "abc" }, Util.Split("abc", ","))
            assert.are.same({ "abc" }, Util.Split("abc", ""))
            assert.are.same({ "" }, Util.Split("", ","))
        end)
    end)

    describe("FormatMoney", function()
        it("formats copper as gold, silver and copper", function()
            assert.are.equal("1g 23s 45c", Util.FormatMoney(12345))
        end)

        it("omits zero units", function()
            assert.are.equal("1g", Util.FormatMoney(10000))
            assert.are.equal("1g 5c", Util.FormatMoney(10005))
            assert.are.equal("1s", Util.FormatMoney(100))
            assert.are.equal("5c", Util.FormatMoney(5))
        end)

        it("shows zero as 0c", function()
            assert.are.equal("0c", Util.FormatMoney(0))
            assert.are.equal("0c", Util.FormatMoney(nil))
        end)

        it("handles negatives and fractions", function()
            assert.are.equal("-1s 50c", Util.FormatMoney(-150))
            assert.are.equal("1c", Util.FormatMoney(1.9))
        end)
    end)
end)
