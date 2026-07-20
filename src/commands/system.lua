local systemCommand = {}


function systemCommand.run(arguments)
    local action = string.lower(arguments[1] or "")

    if action == "clear" then
        return true, ""

    elseif action == "reboot" then
        os.reboot()

    elseif action == "shutdown" then
        os.shutdown()
    end

    return false,
        "Usage: system clear | system reboot | system shutdown"
end


return systemCommand