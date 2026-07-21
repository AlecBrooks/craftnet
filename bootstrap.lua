local OWNER = "AlecBrooks"
local REPOSITORY = "craftnet"
local BRANCH = "main"
local SOURCE_DIRECTORY = "src"

local INSTALL_DIRECTORY = "/craftnet"
local STAGING_DIRECTORY = "/craftnet-update"
local BACKUP_DIRECTORY = "/craftnet-backup"

local DATA_DIRECTORY = "/craftnet-data"
local ROLE_PATH = DATA_DIRECTORY .. "/install-role.lua"

local INSTALLED_LOGO = INSTALL_DIRECTORY .. "/assets/logo.nfp"

local BOOTSTRAP_PATH = "/bootstrap.lua"
local STARTUP_PATH = "/startup.lua"
local STARTUP_COMMAND = 'shell.run("/bootstrap.lua")\n'

local MINIMUM_SPLASH_SECONDS = 2
local arguments = { ... }

local PROFILES = {
    gateway = {
        label = "Gateway",
        program = "main.lua",
        include = function()
            return true
        end,
    },

    host = {
        label = "Host",
        program = "host.lua",
        files = {
            ["host.lua"] = true,
            ["cnet.lua"] = true,
            ["cnetd.lua"] = true,
            ["config.lua"] = true,
            ["assets/logo.nfp"] = true,
            ["lib/cnet.lua"] = true,
            ["lib/modem.lua"] = true,
            ["lib/local_protocol.lua"] = true,
            ["lib/protocol.lua"] = true,
        },
    },
}

local TREE_URL =
    "https://api.github.com/repos/"
    .. OWNER .. "/" .. REPOSITORY
    .. "/git/trees/" .. BRANCH
    .. "?recursive=1"

local RAW_BASE_URL =
    "https://raw.githubusercontent.com/"
    .. OWNER .. "/" .. REPOSITORY
    .. "/" .. BRANCH .. "/"

local API_HEADERS = {
    ["Accept"] = "application/vnd.github+json",
    ["User-Agent"] = "CraftNet-Bootstrap",
    ["X-GitHub-Api-Version"] = "2022-11-28",
}

local EMBEDDED_LOGO = [[22222f9999fff222ff99999f22222f9fff9f22222f99999
2fffff9fff9f2fff2f9fffffff2fff99ff9f2fffffff9ff
2fffff9999ff22222f9999ffff2fff9f9f9f2222ffff9ff
2fffff9f9fff2fff2f9fffffff2fff9ff99f2fffffff9ff
22222f9ff9ff2fff2f9fffffff2fff9fff9f22222fff9ff
]]

local splashStartedAt = os.epoch("utc")
local activeProfile = nil

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalizeRole(value)
    value = string.lower(trim(value))

    if value == "1" or value == "gateway" then
        return "gateway"
    end

    if value == "2"
        or value == "host"
        or value == "client"
    then
        return "host"
    end

    return nil
end

local function ensureDirectory(path)
    if not fs.exists(path) then
        fs.makeDir(path)
    end
end

local function loadSavedRole()
    if not fs.exists(ROLE_PATH)
        or fs.isDir(ROLE_PATH)
    then
        return nil
    end

    local file = fs.open(ROLE_PATH, "r")

    if not file then
        return nil
    end

    local source = file.readAll()
    file.close()

    local value = textutils.unserialize(source)

    if type(value) == "table" then
        return normalizeRole(value.role)
    end

    if type(value) == "string" then
        return normalizeRole(value)
    end

    return normalizeRole(source)
end

local function saveRole(role)
    ensureDirectory(DATA_DIRECTORY)

    local file = fs.open(ROLE_PATH, "w")

    if not file then
        return false, "Could not save installation role."
    end

    file.write(textutils.serialize({ role = role }))
    file.close()

    return true
end

local function chooseRole()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    print("CraftNet installation type")
    print("")
    print("1. Gateway")
    print("   Router, relay, ports, and services.")
    print("")
    print("2. Host")
    print("   Silent network manager, normal shell,")
    print("   cnet command, and developer API.")
    print("")

    while true do
        term.setTextColor(colors.white)
        term.write("Install as gateway or host? ")

        local choice = normalizeRole(read())

        if choice then
            return choice
        end

        term.setTextColor(colors.red)
        print("Enter 1, 2, gateway, or host.")
    end
end

local function resolveRole()
    local requested = normalizeRole(arguments[1])

    if requested then
        local saved, saveError = saveRole(requested)

        if not saved then
            return nil, saveError
        end

        return requested
    end

    local saved = loadSavedRole()

    if saved then
        return saved
    end

    local selected = chooseRole()
    local roleSaved, saveError = saveRole(selected)

    if not roleSaved then
        return nil, saveError
    end

    return selected
end

local function loadLogo()
    local installed = paintutils.loadImage(INSTALLED_LOGO)

    if installed then
        return installed
    end

    return paintutils.parseImage(EMBEDDED_LOGO)
end

local splashLogo = loadLogo()

local function getImageSize(image)
    local imageWidth = 0
    local imageHeight = #image

    for _, row in ipairs(image) do
        imageWidth = math.max(imageWidth, #row)
    end

    return imageWidth, imageHeight
end

local function centerText(y, text, color)
    local width = term.getSize()
    local x = math.max(
        1,
        math.floor((width - #text) / 2) + 1
    )

    term.setBackgroundColor(colors.black)
    term.setTextColor(color or colors.white)
    term.setCursorPos(x, y)
    term.write(text)
end

local function drawSplash(status, detail, statusColor)
    local width, height = term.getSize()
    local imageWidth, imageHeight = getImageSize(splashLogo)

    local imageX = math.max(
        1,
        math.floor((width - imageWidth) / 2) + 1
    )

    local imageY = math.max(
        1,
        math.floor((height - imageHeight) / 2) - 2
    )

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    paintutils.drawImage(splashLogo, imageX, imageY)

    local titleY = math.min(
        height,
        imageY + imageHeight + 1
    )

    local label =
        activeProfile
        and activeProfile.label
        or "Installer"

    centerText(
        titleY,
        "CraftNet " .. label,
        colors.white
    )

    if status and titleY + 2 <= height then
        centerText(
            titleY + 2,
            status,
            statusColor or colors.lightGray
        )
    end

    if detail and titleY + 3 <= height then
        local maximumLength = math.max(1, width - 2)
        local displayed = tostring(detail)

        if #displayed > maximumLength then
            displayed =
                displayed:sub(1, maximumLength - 3)
                .. "..."
        end

        centerText(
            titleY + 3,
            displayed,
            colors.gray
        )
    end
end

local function waitForMinimumSplashTime()
    local elapsedMilliseconds =
        os.epoch("utc") - splashStartedAt

    local remainingSeconds =
        MINIMUM_SPLASH_SECONDS
        - (elapsedMilliseconds / 1000)

    if remainingSeconds > 0 then
        sleep(remainingSeconds)
    end
end

local function deleteIfExists(path)
    if fs.exists(path) then
        fs.delete(path)
    end
end

local function ensureParentDirectory(path)
    local parent = fs.getDir(path)

    if parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
end

local function encodeRepositoryPath(path)
    local encodedSegments = {}

    for segment in path:gmatch("[^/]+") do
        encodedSegments[#encodedSegments + 1] =
            textutils.urlEncode(segment)
    end

    return table.concat(encodedSegments, "/")
end

local function readFailedResponse(requestError, errorResponse)
    local message =
        tostring(requestError or "Unknown HTTP error")

    if errorResponse then
        local responseCode =
            errorResponse.getResponseCode()

        errorResponse.close()

        message =
            "HTTP "
            .. tostring(responseCode)
            .. ": "
            .. message
    end

    return message
end

local function download(url, headers, binary)
    local response,
        requestError,
        errorResponse =
            http.get({
                url = url,
                headers = headers or {},
                binary = binary == true,
                redirect = true,
                timeout = 20,
            })

    if not response then
        return nil,
            readFailedResponse(
                requestError,
                errorResponse
            )
    end

    local contents = response.readAll()
    response.close()

    return contents
end

local function installStartupFile()
    if not fs.exists(BOOTSTRAP_PATH) then
        return false,
            "Bootstrap must be installed as "
            .. BOOTSTRAP_PATH
    end

    local existingSource = nil

    if fs.exists(STARTUP_PATH) then
        if fs.isDir(STARTUP_PATH) then
            return false,
                STARTUP_PATH
                .. " is a directory, not a file."
        end

        local existingFile = fs.open(STARTUP_PATH, "r")

        if not existingFile then
            return false,
                "Could not read " .. STARTUP_PATH
        end

        existingSource = existingFile.readAll()
        existingFile.close()
    end

    if existingSource == STARTUP_COMMAND then
        return true, "Automatic startup already installed."
    end

    if existingSource and existingSource ~= "" then
        return false,
            STARTUP_PATH
            .. " already exists. CraftNet did not overwrite it."
    end

    local startupFile = fs.open(STARTUP_PATH, "w")

    if not startupFile then
        return false,
            "Could not create " .. STARTUP_PATH
    end

    startupFile.write(STARTUP_COMMAND)
    startupFile.close()

    return true, "Automatic startup installed."
end

local function shouldIncludeFile(profile, relativePath)
    if profile.include then
        return profile.include(relativePath)
    end

    return profile.files
        and profile.files[relativePath] == true
end

local function getRepositoryFiles(profile)
    drawSplash(
        "Checking for updates...",
        "Reading repository file list."
    )

    local manifestSource, downloadError =
        download(TREE_URL, API_HEADERS, false)

    if not manifestSource then
        return nil,
            "Could not read repository tree: "
            .. tostring(downloadError)
    end

    local decodeSucceeded, manifest =
        pcall(
            textutils.unserializeJSON,
            manifestSource
        )

    if not decodeSucceeded
        or type(manifest) ~= "table"
        or type(manifest.tree) ~= "table"
    then
        return nil,
            "GitHub returned an invalid repository tree."
    end

    if manifest.truncated == true then
        return nil,
            "GitHub truncated the repository tree."
    end

    local files = {}
    local found = {}
    local sourcePrefix = SOURCE_DIRECTORY .. "/"

    for _, entry in ipairs(manifest.tree) do
        if entry.type == "blob"
            and type(entry.path) == "string"
            and entry.path:sub(1, #sourcePrefix)
                == sourcePrefix
        then
            local relativePath =
                entry.path:sub(#sourcePrefix + 1)

            if relativePath ~= ""
                and shouldIncludeFile(
                    profile,
                    relativePath
                )
            then
                files[#files + 1] = {
                    repositoryPath = entry.path,
                    relativePath = relativePath,
                }

                found[relativePath] = true
            end
        end
    end

    if #files == 0 then
        return nil,
            "No files were found for the "
            .. profile.label
            .. " profile."
    end

    if not found[profile.program] then
        return nil,
            "The repository does not contain "
            .. SOURCE_DIRECTORY
            .. "/"
            .. profile.program
            .. "."
    end

    if profile.files then
        for requiredPath in pairs(profile.files) do
            if not found[requiredPath] then
                return nil,
                    "Host profile is missing "
                    .. SOURCE_DIRECTORY
                    .. "/"
                    .. requiredPath
                    .. "."
            end
        end
    end

    table.sort(
        files,
        function(left, right)
            return left.repositoryPath
                < right.repositoryPath
        end
    )

    return files
end

local function writeDownloadedFile(relativePath, contents)
    local destination =
        fs.combine(STAGING_DIRECTORY, relativePath)

    ensureParentDirectory(destination)

    local file = fs.open(destination, "wb")

    if not file then
        return false,
            "Could not write " .. destination
    end

    file.write(contents)
    file.close()

    return true
end

local function downloadRepository(files)
    deleteIfExists(STAGING_DIRECTORY)
    fs.makeDir(STAGING_DIRECTORY)

    for index, fileInfo in ipairs(files) do
        drawSplash(
            "Updating CraftNet...",
            "["
                .. tostring(index)
                .. "/"
                .. tostring(#files)
                .. "] "
                .. fileInfo.relativePath
        )

        local url =
            RAW_BASE_URL
            .. encodeRepositoryPath(
                fileInfo.repositoryPath
            )

        local contents, downloadError =
            download(url, nil, true)

        if not contents then
            deleteIfExists(STAGING_DIRECTORY)

            return false,
                "Could not download "
                .. fileInfo.repositoryPath
                .. ": "
                .. tostring(downloadError)
        end

        local written, writeError =
            writeDownloadedFile(
                fileInfo.relativePath,
                contents
            )

        if not written then
            deleteIfExists(STAGING_DIRECTORY)
            return false, writeError
        end
    end

    return true
end

local function installUpdate()
    drawSplash(
        "Installing update...",
        "Activating downloaded files."
    )

    deleteIfExists(BACKUP_DIRECTORY)

    local hadExistingInstall =
        fs.exists(INSTALL_DIRECTORY)

    if hadExistingInstall then
        local movedOldInstall, moveError =
            pcall(
                fs.move,
                INSTALL_DIRECTORY,
                BACKUP_DIRECTORY
            )

        if not movedOldInstall then
            return false,
                "Could not preserve current install: "
                .. tostring(moveError)
        end
    end

    local movedNewInstall, moveError =
        pcall(
            fs.move,
            STAGING_DIRECTORY,
            INSTALL_DIRECTORY
        )

    if not movedNewInstall then
        if hadExistingInstall
            and fs.exists(BACKUP_DIRECTORY)
            and not fs.exists(INSTALL_DIRECTORY)
        then
            pcall(
                fs.move,
                BACKUP_DIRECTORY,
                INSTALL_DIRECTORY
            )
        end

        return false,
            "Could not activate update: "
            .. tostring(moveError)
    end

    deleteIfExists(BACKUP_DIRECTORY)

    return true
end

local function recoverInterruptedUpdate()
    if not fs.exists(INSTALL_DIRECTORY)
        and fs.exists(BACKUP_DIRECTORY)
    then
        pcall(
            fs.move,
            BACKUP_DIRECTORY,
            INSTALL_DIRECTORY
        )

    elseif fs.exists(INSTALL_DIRECTORY)
        and fs.exists(BACKUP_DIRECTORY)
    then
        deleteIfExists(BACKUP_DIRECTORY)
    end

    deleteIfExists(STAGING_DIRECTORY)
end

local function updateCraftNet(profile)
    local files, treeError =
        getRepositoryFiles(profile)

    if not files then
        return false, treeError
    end

    local downloaded, downloadError =
        downloadRepository(files)

    if not downloaded then
        return false, downloadError
    end

    local installed, installError =
        installUpdate()

    if not installed then
        deleteIfExists(STAGING_DIRECTORY)
        return false, installError
    end

    return true,
        tostring(#files)
        .. " files installed for "
        .. profile.label
        .. "."
end

recoverInterruptedUpdate()

local role, roleError = resolveRole()

if not role then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    printError(tostring(roleError))
    return
end

activeProfile = PROFILES[role]

local startupInstalled, startupResult =
    installStartupFile()

drawSplash(
    "Starting CraftNet...",
    startupInstalled
        and startupResult
        or tostring(startupResult),
    startupInstalled
        and colors.lightGray
        or colors.red
)

local updated, updateResult =
    updateCraftNet(activeProfile)

if updated then
    local detail = tostring(updateResult)

    if startupInstalled then
        detail =
            detail
            .. " Automatic startup ready."
    else
        detail =
            detail
            .. " Startup warning: "
            .. tostring(startupResult)
    end

    drawSplash(
        "Update complete.",
        detail,
        startupInstalled
            and colors.lime
            or colors.yellow
    )
else
    local detail = tostring(updateResult)

    if not startupInstalled then
        detail =
            detail
            .. " Startup warning: "
            .. tostring(startupResult)
    end

    drawSplash(
        "Update failed.",
        detail,
        colors.red
    )
end

waitForMinimumSplashTime()

local program =
    fs.combine(
        INSTALL_DIRECTORY,
        activeProfile.program
    )

if fs.exists(program) then
    shell.run(program)
else
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    printError(
        "CraftNet "
        .. activeProfile.label
        .. " is not installed."
    )

    if not updated then
        printError(tostring(updateResult))
    end
end
