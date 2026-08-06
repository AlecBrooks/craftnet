local ids = {}


-- Returns a stateful generator function producing IDs of
-- the form "computerId-epochMillis-counter". The counter
-- guarantees uniqueness for multiple IDs created on the
-- same computer within the same millisecond.
function ids.newGenerator()
    local counter = 0

    return function()
        counter = counter + 1

        return table.concat({
            tostring(os.getComputerID()),
            tostring(os.epoch("utc")),
            tostring(counter),
        }, "-")
    end
end


return ids
