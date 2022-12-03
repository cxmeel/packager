--!strict
local CollectionService = game:GetService("CollectionService")

local T = require(script["init.d"])
local DumpParser = require(script.Parent.DumpParser)

local Dictionary = require(script.Util.Dictionary)
local ShortId = require(script.Util.ShortId)

local Packager = {}

Packager.__index = Packager

local function createRef(_: Instance): string
	return ShortId(8)
end

local function encodeValue(value: any?)
	return {
		Type = typeof(value),
		Value = value,
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
	refs: { [Instance]: string }
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
			return encodeValue(value), key
		end)
	end

	for property in changedProperties do
		local propertyValue = encodeValue((instance :: any)[property])

		if propertyValue.Type == "Instance" then
			local linkedRef = refs[propertyValue.Value :: Instance]

			if linkedRef == nil then
				propertyValue = nil :: any
			else
				propertyValue.Type = "Ref"
				propertyValue.Value = linkedRef
			end
		end

		node.Properties[property] = propertyValue
	end

	return node
end

function Packager:CreatePackageFlat(instance: Instance): T.FlatPackage
	local descendants = instance:GetDescendants()
	local refs = { [instance] = createRef(instance) }

	for _, descendant in descendants do
		refs[descendant] = createRef(descendant)
	end

	local rootNode = self:createFlatTreeNode(instance, refs)
	local tree = { [rootNode.Ref] = rootNode }

	for _, descendant in descendants do
		local node = self:createFlatTreeNode(descendant, refs)
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

	local function populateTree(node: T.TreeNode)
		local flatNode: T.FlatTreeNode = {
			Name = node.Name,
			ClassName = node.ClassName,
			Properties = node.Properties,
			Attributes = node.Attributes,
			Tags = node.Tags,
			Ref = node.Ref,
		}

		tree[flatNode.Ref] = flatNode

		if not node.Children then
			return
		end

		for _, child in node.Children do
			populateTree(child)
		end
	end

	populateTree(package.Tree)

	return {
		Refs = refs,
		RootRef = package.Tree.Ref,
		Tree = tree,
	}
end

function Packager:CreatePackage(rootInstance: Instance): T.Package
	local flatPackage = self:CreatePackageFlat(rootInstance)
	return self:ConvertToPackage(flatPackage)
end

return Packager
