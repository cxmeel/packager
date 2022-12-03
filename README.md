# Packager

Packages up an Instance or tree of Instances into a single table.
Supports linking of Instance-based properties to their corresponding
Instance (as long as the Instance is within the tree being packaged).

## Usage

```lua
local Packager = require(script.Parent.Packager)

-- Create a new Packager from the latest Roblox API dump
local packager = Packager.fetchFromServer()

local tree = packager:CreatePackage(workspace.MyModel)
--[[
  {
    Refs = {
      [MyModel<Model>] = "AABBCC",
    },
    Tree = {
      Name = "MyModel",
      ClassName = "Model",
      Ref = "AABBCC",
      Properties = {
        PrimaryPart = {
          Type = "Ref",
          Value = "BBCCDD",
        },
      },
      Children = {
        {
          Name = "Part",
          ClassName = "Part",
          Ref = "BBCCDD",
          ...,
        },
      },
      Attributes = {
        OwnerId = {
          Type = "number",
          Value = 1233456789,
        },
      },
      Tags = { "Tag1", "Tag2" },
    },
  }
]]
```
