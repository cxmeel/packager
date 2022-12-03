--!strict
--[=[
	@class Packager
]=]
local CollectionService = game:GetService("CollectionService")

local T = require(script["init.d"])
local DumpParser = require(script.Parent.DumpParser)

local Dictionary = require(script.Util.Dictionary)
local ShortId = require(script.Util.ShortId)

local Packager = {}

Packager.__index = Packager

--[=[
	@prop Types {}
	@within Packager

	A reference to the `Types` module, which contains various
	types used within the packager.
]=]
Packager.Types = T

local REF_KEY = "REF"

local VALUE_TYPE_REMAP = {
	bool = "boolean",
	float = "number",
	double = "number",
	int = "number",
	int64 = "number",
	string = "string",
	void = "nil",
}

--[=[
	@prop DEFAULT_VALUE_ENCODER ValueEncoder
	@within Packager

	The default value encoder used by the packager. It
	encodes values as-is, with the exception of Enums,
	which are encoded as a table of `Type = EnumType`
	and `Value = EnumItem.Name`.
]=]
function Packager.DEFAULT_VALUE_ENCODER(value: any, valueType: string)
	valueType = VALUE_TYPE_REMAP[valueType] or valueType

	if valueType == "Enum" then
		return {
			Type = tostring(value.EnumType),
			Value = value.Name,
		}
	end

	return value, valueType
end

--[=[
	@prop DEFAULT_VALUE_DECODER ValueDecoder
	@within Packager

	The default value decoder used by the packager. It
	decodes values as-is, with the exception of Enums,
	which are decoded from a table of `Type = EnumType`
	and `Value = EnumItem.Name`.
]=]
function Packager.DEFAULT_VALUE_DECODER(value: T.Property): any
	if value.Type == "Enum" then
		local enumInfo = value.Value
		return Enum[enumInfo.Type][enumInfo.Value]
	end

	return value.Value
end

local DEFAULT_PACKAGER_CONFIG: T.PackageConfig = {
	valueEncoder = Packager.DEFAULT_VALUE_ENCODER,
}

local DEFAULT_BUILDER_CONFIG: T.BuilderConfig = {
	valueDecoder = Packager.DEFAULT_VALUE_DECODER,
}

local function createRef(_: Instance): string
	return ShortId(8)
end

local function encodeValue(value: any?, valueType: string, valueEncoder: T.ValueEncoder)
	local encodedValue, encodedValueType = valueEncoder(value, valueType)

	return {
		Type = encodedValueType or valueType,
		Value = encodedValue,
	}
end

--[=[
	@function new
	@within Packager
	@param dump APIDump | DumpParser
	@return Packager

	Creates a new packager instance. The packager can be used
	to package instances into a tree structure, and to build
	instances from a tree structure.
]=]
function Packager.new(dump: T.DumpParser | T.APIDump)
	local self = setmetatable({}, Packager)

	if typeof(dump.GetClasses) == "function" then
		self._dump = dump
	elseif typeof(dump) == "table" then
		self._dump = DumpParser.new(dump)
	end

	return self
end

--[=[
	@function fetchFromServer
	@within Packager
	@param hashOrVersion string
	@return Packager

	Creates a new packager instance by fetching the API dump
	from Roblox server. This is a convenience method for
	`Packager.new(DumpParser.fetchFromServer(hashOrVersion))`.
]=]
function Packager.fetchFromServer(hashOrVersion: string?)
	local dump = DumpParser.fetchFromServer(hashOrVersion)
	return Packager.new(dump)
end

--[=[
	@method createFlatTreeNode
	@within Packager
	@private
	@param instance Instance
	@param refs { [Instance]: string }
	@param config PackageConfig
	@return FlatTreeNode

	Creates a flat tree node from an instance.
]=]
function Packager:createFlatTreeNode(
	instance: Instance,
	refs: { [Instance]: string },
	config: T.PackageConfig
): T.FlatTreeNode
	local node = {}

	local changedProperties = self._dump:GetChangedProperties(
		instance,
		DumpParser.Filter.Invert(DumpParser.Filter.ReadOnly)
	)

	node.Ref = refs[instance]
	node.Name = instance.Name
	node.ClassName = instance.ClassName
	node.Properties = {}

	local instanceTags = CollectionService:GetTags(instance)
	local instanceAttributes = instance:GetAttributes()

	if #instanceTags > 0 then
		node.Tags = instanceTags
	end

	if next(instanceAttributes) then
		node.Attributes = Dictionary.map(instanceAttributes, function(value, key)
			return encodeValue(value, typeof(value), config.valueEncoder), key
		end)
	end

	for property, propertyMeta in changedProperties do
		if property == "Name" then
			continue
		end

		local propertyValueType = if propertyMeta.ValueType.Category == "Class"
			then "Instance"
			elseif propertyMeta.ValueType.Category == "Enum" then "Enum"
			else propertyMeta.ValueType.Name

		local propertyValue =
			encodeValue((instance :: any)[property], propertyValueType, config.valueEncoder)

		if propertyValueType == "Instance" then
			local linkedRef = refs[propertyValue.Value :: Instance]

			if linkedRef == nil then
				propertyValue = nil :: any
			else
				propertyValue.Type = REF_KEY
				propertyValue.Value = linkedRef
			end
		end

		node.Properties[property] = propertyValue
	end

	return node
end

--[=[
	@method CreatePackageFlat
	@within Packager
	@param rootInstance Instance
	@param config PackageConfig
	@return FlatPackage

	Creates a new package with a flat tree structure from a
	given root Instance.
]=]
function Packager:CreatePackageFlat(rootInstance: Instance, config: T.PackageConfig?): T.FlatPackage
	local options: T.PackageConfig = Dictionary.merge(DEFAULT_PACKAGER_CONFIG, config)

	local descendants = rootInstance:GetDescendants()
	local refs = { [rootInstance] = createRef(rootInstance) }

	for _, descendant in descendants do
		refs[descendant] = createRef(descendant)
	end

	local rootNode = self:createFlatTreeNode(rootInstance, refs, options)
	local tree = { [rootNode.Ref] = rootNode }

	for _, descendant in descendants do
		local node = self:createFlatTreeNode(descendant, refs, options)
		tree[node.Ref] = node
	end

	return {
		Refs = refs,
		RootRef = rootNode.Ref,
		Tree = tree,
	}
end

--[=[
	@method ConvertToPackage
	@within Packager
	@param flatPackage FlatPackage
	@return Package

	Converts a flat package to a package with a normal tree
	structure (i.e. each node has a `Children` property).
]=]
function Packager:ConvertToPackage(flatPackage: T.FlatPackage): T.Package
	local flatRootNode = flatPackage.Tree[flatPackage.RootRef]

	local function buildTree(rootNode: T.FlatTreeNode)
		local children = {}

		local newNode: T.TreeNode = {
			Name = rootNode.Name,
			ClassName = rootNode.ClassName,
			Properties = rootNode.Properties,
			Attributes = rootNode.Attributes,
			Tags = rootNode.Tags,
			Ref = rootNode.Ref,
		}

		for _, node in flatPackage.Tree do
			if node.Properties.Parent == nil then
				continue
			end

			if node.Properties.Parent.Value == rootNode.Ref then
				table.insert(children, buildTree(node))
				node.Properties.Parent = nil :: any
			end
		end

		if #children > 0 then
			newNode.Children = children
		end

		return newNode
	end

	return {
		Refs = flatPackage.Refs,
		Tree = buildTree(flatRootNode),
	}
end

--[=[
	@method ConvertToPackageFlat
	@within Packager
	@param package Package
	@return FlatPackage

	Converts a package with a normal tree structure to a flat
	structure (i.e. the tree is an array of tree nodes---Parents
	are determined by reference strings).
]=]
function Packager:ConvertToPackageFlat(package: T.Package): T.FlatPackage
	local refs = package.Refs
	local tree = {}

	local function populateTree(node: T.TreeNode, parentNode: T.TreeNode?)
		local flatNode: T.FlatTreeNode = {
			Name = node.Name,
			ClassName = node.ClassName,
			Properties = node.Properties,
			Attributes = node.Attributes,
			Tags = node.Tags,
			Ref = node.Ref,
		}

		tree[flatNode.Ref] = flatNode

		if parentNode then
			flatNode.Properties.Parent = {
				Type = REF_KEY,
				Value = parentNode.Ref,
			}
		end

		if not node.Children then
			return
		end

		for _, child in node.Children do
			populateTree(child, node)
		end
	end

	populateTree(package.Tree, nil)

	return {
		Refs = refs,
		RootRef = package.Tree.Ref,
		Tree = tree,
	}
end

--[=[
	@method CreatePackage
	@within Packager
	@param rootInstance Instance
	@param config PackageConfig
	@return Package

	Creates a new package from a given root Instance. This
	function is a wrapper around `CreatePackageFlat` and
	`ConvertToPackage`.
]=]
function Packager:CreatePackage(rootInstance: Instance, config: T.PackageConfig?): T.Package
	local flatPackage = self:CreatePackageFlat(rootInstance, config)
	return self:ConvertToPackage(flatPackage)
end

--[=[
	@method BuildFromPackage
	@within Packager
	@param package Package | FlatPackage
	@param config BuildConfig
	@return Instance

	Builds an Instance from a given package. The returned Instance
	is the root of the built tree, and is not assigned a Parent. You
	must assign the root to a Parent yourself.
]=]
function Packager:BuildFromPackage<T>(
	package: T.Package | T.FlatPackage,
	config: T.BuilderConfig?
): T.RobloxInstance<T>
	local options: T.BuilderConfig = Dictionary.merge(DEFAULT_BUILDER_CONFIG, config)
	local isFlatPackage = package.RootRef ~= nil

	local flatPackage = isFlatPackage and package or self:ConvertToPackageFlat(package)

	local instances = {}

	for ref, node in flatPackage.Tree do
		local instance = Instance.new(node.ClassName)
		instance.Name = node.Name

		instances[ref] = instance
	end

	for ref, node in flatPackage.Tree do
		local instance = instances[ref]

		for propertyName, property in node.Properties do
			if property.Type == REF_KEY then
				local linkedInstance = instances[property.Value]

				if linkedInstance == nil then
					continue
				end

				instance[propertyName] = linkedInstance
				continue
			end

			local decodedValue = options.valueDecoder(property)
			instance[propertyName] = decodedValue
		end

		if node.Attributes then
			for key, value in node.Attributes do
				local decodedValue = options.valueDecoder(value)
				instance:SetAttribute(key, decodedValue)
			end
		end

		if node.Tags then
			for _, tag in node.Tags do
				CollectionService:AddTag(instance, tag)
			end
		end
	end

	return instances[flatPackage.RootRef]
end

return Packager
