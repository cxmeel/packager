--!strict
local DumpParser = require(script.Parent.Parent.DumpParser)
local DPT = DumpParser.Types

export type APIDump = DPT.APIDump
export type DumpParser = typeof(DumpParser.new({ Classes = {} }))

export type Property = {
	Type: string,
	Value: any,
}

type CommonTreeNode = {
	Name: string,
	ClassName: string,
	Properties: { [string]: Property },
	Attributes: { [string]: Property }?,
	Tags: { string }?,
	Ref: string,
}

export type TreeNode = CommonTreeNode & {
	Children: { TreeNode }?,
}

export type FlatTreeNode = CommonTreeNode

export type Package = {
	Refs: { [Instance]: string },
	Tree: TreeNode,
}

export type FlatPackage = {
	Refs: { [Instance]: string },
	RootRef: string,
	Tree: { [string]: FlatTreeNode },
}

export type ValueEncoder = (value: any, valueType: string) -> (any, string?)

export type ValueDecoder = (value: Property) -> any

export type PackageConfig = {
	valueEncoder: ValueEncoder,
}

export type BuilderConfig = {
	valueDecoder: ValueDecoder,
}

return {}
