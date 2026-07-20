local program = "/craftnet/main.lua"

if fs.exists(program) then
    shell.run(program)
else
    printError("CraftNet development file not found:")
    print(program)
end
