--!strict
local CollectionService = game:GetService("CollectionService")

local T = require(script["init.d"])
local DumpParser = require(script.Parent.DumpParser)

local Dictionary = require(script.Util.Dictionary)
local ShortId = require(script.Util.ShortId)

local Packager = {}

Packager.__index = Packager

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

function Packager.new(dump: T.DumpParser | T.APIDump)
	local self = setmetatable({}, Packager)

	if typeof(dump.GetClasses) == "function" then
		self._dump = dump
	elseif typeof(dump) == "table" then
		self._dump = DumpParser.new(dump)
	end

	return self
end

function Packager.fetchFromServer(hashOrVersion: string?)
	local dump = DumpParser.fetchFromServer(hashOrVersion)
	return Packager.new(dump)
end

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

function Packager:CreatePackageFlat(instance: Instance, config: T.PackageConfig?): T.FlatPackage
	local options: T.PackageConfig = Dictionary.merge(DEFAULT_PACKAGER_CONFIG, config)

	local descendants = instance:GetDescendants()
	local refs = { [instance] = createRef(instance) }

	for _, descendant in descendants do
		refs[descendant] = createRef(descendant)
	end

	local rootNode = self:createFlatTreeNode(instance, refs, options)
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

function Packager:CreatePackage(rootInstance: Instance, config: T.PackageConfig?): T.Package
	local flatPackage = self:CreatePackageFlat(rootInstance, config)
	return self:ConvertToPackage(flatPackage)
end

function Packager:BuildFromPackage(
	package: T.Package | T.FlatPackage,
	config: T.BuilderConfig?
): Instance
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
