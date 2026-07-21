local cnetd = require("cnetd")


local function ensureCraftNetCommandPath()
    local currentPath = shell.path()

    if not currentPath:find(
        "/craftnet",
        1,
        true
    ) then
        shell.setPath(
            currentPath .. ":/craftnet"
        )
    end
end


local function daemonLoop()
    cnetd.run()
end


local function shellLoop()
    ensureCraftNetCommandPath()

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    shell.run("/rom/programs/shell.lua")
end


parallel.waitForAny(
    daemonLoop,
    shellLoop
)

cnetd.shutdown()
