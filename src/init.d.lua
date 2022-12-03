--!strict
--[=[
	@class Types
]=]
local DumpParser = require(script.Parent.Parent.DumpParser)
local DPT = DumpParser.Types

--[=[
	@type APIDump DumpParser.APIDump
	@within Types

	See [DumpParser.APIDump](https://csqrl.github.io/dump-parser/api/Types#APIDump).
]=]
export type APIDump = DPT.APIDump

--[=[
	@type DumpParser DumpParser
	@within Types

	See [DumpParser](https://csqrl.github.io/dump-parser/api/Dump).
]=]
export type DumpParser = typeof(DumpParser.new({ Classes = {} }))

--[=[
	@interface Property
	@within Types
	.Type string
	.Value any

	Represents a property/attribute of an Instance.
]=]
export type Property = {
	Type: string,
	Value: any,
}

--[=[
	@interface CommonTreeNode
	@within Types
	@private
	.Name string
	.ClassName string
	.Properties { [string]: Property }
	.Attributes { [string]: Property }?
	.Tags { string }?
	.Ref string
]=]
type CommonTreeNode = {
	Name: string,
	ClassName: string,
	Properties: { [string]: Property },
	Attributes: { [string]: Property }?,
	Tags: { string }?,
	Ref: string,
}

--[=[
	@type TreeNode CommonTreeNode & { Children: { TreeNode }? }
	@within Types
]=]
export type TreeNode = CommonTreeNode & {
	Children: { TreeNode }?,
}

--[=[
	@type FlatTreeNode CommonTreeNode
	@within Types
]=]
export type FlatTreeNode = CommonTreeNode

--[=[
	@interface Package
	@within Types
	.Refs { [Instance]: string }
	.Tree TreeNode

	A package with a normal tree structure (i.e. each node has a
	`Children` property).
]=]
export type Package = {
	Refs: { [Instance]: string },
	Tree: TreeNode,
}

--[=[
	@interface FlatPackage
	@within Types
	.Refs { [Instance]: string }
	.RootRef string
	.Tree { [string]: FlatTreeNode }

	A flat package does not have a normal tree structure. The tree
	is an array of nodes. Each node that has a parent has a `Parent`
	property that is a reference to the parent node's `Ref` property.
]=]
export type FlatPackage = {
	Refs: { [Instance]: string },
	RootRef: string,
	Tree: { [string]: FlatTreeNode },
}

--[=[
	@type ValueEncoder (value: any, valueType: string) -> (any, string?)
	@within Types
]=]
export type ValueEncoder = (value: any, valueType: string) -> (any, string?)

--[=[
	@type ValueDecoder (value: any, valueType: string) -> (any, string?)
	@within Types
]=]
export type ValueDecoder = (value: Property) -> any

--[=[
	@interface PackageConfig
	@within Types
	.valueEncoder ValueEncoder?
]=]
export type PackageConfig = {
	valueEncoder: ValueEncoder,
}

--[=[
	@interface BuilderConfig
	@within Types
	.valueDecoder ValueDecoder?
]=]
export type BuilderConfig = {
	valueDecoder: ValueDecoder,
}

--[=[
	@type RobloxInstance<T> Instance & T
	@within Types
]=]
export type RobloxInstance<T> = Instance & T

return {}
