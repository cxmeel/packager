--!strict
local ALPHABET = string.split("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "")

local GeneratedIds = {}

local function GenerateShortUUID(maxLength: number, alphabet: string?): string
	alphabet = alphabet or ALPHABET
	maxLength = maxLength or 10

	local generatedId = table.create(maxLength, "0")
	local alphabetLength = #ALPHABET

	for i = 1, maxLength do
		local randomIndex = math.random(1, alphabetLength)
		generatedId[i] = ALPHABET[randomIndex]
	end

	local generatedIdString = table.concat(generatedId, "")

	if GeneratedIds[generatedIdString] then
		return GenerateShortUUID(maxLength)
	end

	GeneratedIds[generatedIdString] = true

	return generatedIdString
end

return GenerateShortUUID
