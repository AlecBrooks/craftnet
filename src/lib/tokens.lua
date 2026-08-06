local validate = require("lib.validate")

local tokens = {}


tokens.RETURN_TOKEN_LENGTH = 24

local RETURN_TOKEN_ALPHABET =
    "abcdefghijklmnopqrstuvwxyz"
    .. "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    .. "0123456789"


function tokens.isValidReturnToken(value)
    return validate.isTokenLike(value, 8, 64)
end


-- Generates a random return token. If isTaken is given, it
-- is called with each candidate token and should return
-- true when that token is already in use, so a fresh one
-- is generated instead.
function tokens.newReturnToken(isTaken)
    local token

    repeat
        local characters = {}

        for index = 1, tokens.RETURN_TOKEN_LENGTH do
            local position =
                math.random(
                    1,
                    #RETURN_TOKEN_ALPHABET
                )

            characters[index] =
                RETURN_TOKEN_ALPHABET:sub(
                    position,
                    position
                )
        end

        token = table.concat(characters)
    until not isTaken or not isTaken(token)

    return token
end


return tokens
