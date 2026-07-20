local OWNER = "AlecBrooks"
local REPOSITORY = "craftnet"
local BRANCH = "main"
local SOURCE_DIRECTORY = "src"

local INSTALL_DIRECTORY = "/craftnet"
local STAGING_DIRECTORY = "/craftnet-update"
local BACKUP_DIRECTORY = "/craftnet-backup"

local PROGRAM = INSTALL_DIRECTORY .. "/main.lua"
local INSTALLED_LOGO = INSTALL_DIRECTORY .. "/assets/logo.nfp"

local MINIMUM_SPLASH_SECONDS = 5

local TREE_URL =
    "https://api.github.com/repos/"
    .. OWNER
    .. "/"
    .. REPOSITORY
    .. "/git/trees/"
    .. BRANCH
    .. "?recursive=1"

local RAW_BASE_URL =
    "https://raw.githubusercontent.com/"
    .. OWNER
    .. "/"
    .. REPOSITORY
    .. "/"
    .. BRANCH
    .. "/"

local API_HEADERS = {
    ["Accept"] = "application/vnd.github+json",
    ["User-Agent"] = "CraftNet-Bootstrap",
    ["X-GitHub-Api-Version"] = "2022-11-28",
}

-- First-install fallback. Once CraftNet is installed, the updater
-- loads /craftnet/assets/logo.nfp instead.
local EMBEDDED_LOGO = [[22222f9999fff222ff99999f22222f9fff9f22222f99999
2fffff9fff9f2fff2f9fffffff2fff99ff9f2fffffff9ff
2fffff9999ff22222f9999ffff2fff9f9f9f2222ffff9ff
2fffff9f9fff2fff2f9fffffff2fff9ff99f2fffffff9ff
22222f9ff9ff2fff2f9fffffff2fff9fff9f22222fff9ff
]]

local splashStartedAt = os.epoch("utc")

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
    local imageWidth, imageHeight =
        getImageSize(splashLogo)

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

    paintutils.drawImage(
        splashLogo,
        imageX,
        imageY
    )

    local titleY = math.min(
        height,
        imageY + imageHeight + 1
    )

    centerText(
        titleY,
        "CraftNet Gateway",
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

    if parent ~= ""
        and not fs.exists(parent)
    then
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

local function readFailedResponse(
    requestError,
    errorResponse
)
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

local function getRepositoryFiles()
    drawSplash(
        "Checking for updates...",
        "Reading repository file list."
    )

    local manifestSource, downloadError =
        download(
            TREE_URL,
            API_HEADERS,
            false
        )

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
    local sourcePrefix =
        SOURCE_DIRECTORY .. "/"

    local foundMainProgram = false

    for _, entry in ipairs(manifest.tree) do
        if entry.type == "blob"
            and type(entry.path) == "string"
            and entry.path:sub(
                1,
                #sourcePrefix
            ) == sourcePrefix
        then
            local relativePath =
                entry.path:sub(
                    #sourcePrefix + 1
                )

            if relativePath ~= "" then
                files[#files + 1] = {
                    repositoryPath = entry.path,
                    relativePath = relativePath,
                }

                if relativePath == "main.lua" then
                    foundMainProgram = true
                end
            end
        end
    end

    if #files == 0 then
        return nil,
            "No files were found under src/."
    end

    if not foundMainProgram then
        return nil,
            "The repository does not contain src/main.lua."
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

local function writeDownloadedFile(
    relativePath,
    contents
)
    local destination =
        fs.combine(
            STAGING_DIRECTORY,
            relativePath
        )

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
        local movedOldInstall,
            moveError =
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

    local movedNewInstall,
        moveError =
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

local function updateCraftNet()
    local files, treeError =
        getRepositoryFiles()

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
        .. " files installed."
end

recoverInterruptedUpdate()
drawSplash(
    "Starting CraftNet...",
    "Preparing updater."
)

local updated, updateResult =
    updateCraftNet()

if updated then
    drawSplash(
        "Update complete.",
        updateResult,
        colors.lime
    )
else
    drawSplash(
        "Update failed.",
        tostring(updateResult),
        colors.red
    )
end

waitForMinimumSplashTime()

if fs.exists(PROGRAM) then
    shell.run(PROGRAM)
else
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    printError("CraftNet is not installed.")

    if not updated then
        printError(tostring(updateResult))
    end
end
