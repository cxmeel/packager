--!strict
local function merge<T>(...: any): T
	local result = {}

	for dictionaryIndex = 1, select("#", ...) do
		local dictionary = select(dictionaryIndex, ...)

		if type(dictionary) ~= "table" then
			continue
		end

		for key, value in pairs(dictionary) do
			result[key] = value
		end
	end

	return result
end

local function keys<K, V>(dictionary: { [K]: V }): { K }
	local result = {}

	for key in pairs(dictionary) do
		table.insert(result, key)
	end

	return result
end

local function values<K, V>(dictionary: { [K]: V }): { V }
	local result = {}

	for _, value in pairs(dictionary) do
		table.insert(result, value)
	end

	return result
end

local function map<K, V, X, Y>(
	dictionary: { [K]: V },
	mapper: (value: V, key: K, dictionary: { [K]: V }) -> (Y?, X?)
): { [X]: Y }
	local mapped = {}

	for key, value in pairs(dictionary) do
		local mappedValue, mappedKey = mapper(value, key, dictionary)
		mapped[mappedKey or key] = mappedValue
	end

	return mapped
end

return {
	keys = keys,
	map = map,
	merge = merge,
	values = values,
}
