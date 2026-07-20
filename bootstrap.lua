local OWNER = "AlecBrooks"
local REPOSITORY = "craftnet"
local BRANCH = "main"
local SOURCE_DIRECTORY = "src"

local INSTALL_DIRECTORY = "/craftnet"
local STAGING_DIRECTORY = "/craftnet-update"
local BACKUP_DIRECTORY = "/craftnet-backup"

local PROGRAM = INSTALL_DIRECTORY .. "/main.lua"

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
    ["X-GitHub-Api-Version"] = "2026-03-10",
}


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

    print(
        "Downloading "
        .. tostring(#files)
        .. " files..."
    )

    for index, fileInfo in ipairs(files) do
        print(
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


term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

recoverInterruptedUpdate()

print("Updating CraftNet...")

local updated, updateResult =
    updateCraftNet()

if updated then
    print("Update complete.")
    print(updateResult)
else
    printError(
        "Update failed: "
        .. tostring(updateResult)
    )

    print("Using cached version.")
end

if fs.exists(PROGRAM) then
    shell.run(PROGRAM)
else
    printError("CraftNet is not installed.")
end