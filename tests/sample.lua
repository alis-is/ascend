local test = TEST or require "u-test"

test["ascend"] = function()
    test.assert(true)
end


if not TEST then
    test.summary()
end
