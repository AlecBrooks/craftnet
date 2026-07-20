local url =
    "https://raw.githubusercontent.com/alecbrooks/craftnet/main/src/main.lua"

local directory = "/craftnet"
local program = directory .. "/main.lua"
local temporary = directory .. "/main.lua.new"

if not fs.exists(directory) then
    fs.makeDir(directory)
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

print("Updating CraftNet...")

local response, downloadError = http.get(url)

if response then
    local source = response.readAll()
    response.close()

    local file = fs.open(temporary, "w")

    if file then
        file.write(source)
        file.close()

        if fs.exists(program) then
            fs.delete(program)
        end

        fs.move(temporary, program)
        print("Update complete.")
    else
        printError("Could not write update.")
    end
else
    printError("Update failed: " .. tostring(downloadError))
    print("Using cached version.")
end

if fs.exists(program) then
    shell.run(program)
else
    printError("CraftNet is not installed.")
end