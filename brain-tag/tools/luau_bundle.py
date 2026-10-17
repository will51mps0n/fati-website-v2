"""Bundle Brain Tag's pure shared modules into one standalone Luau script.

Roblox modules load each other with `require(script.Parent.Name)`. Outside
Roblox there is no `script`, so this wraps every module in a loader function,
hands it a fake `script`, and swaps in a `require` that resolves those fake
references. Only modules with no Roblox dependencies can be bundled.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "src" / "shared"

PURE_MODULES = ["Config", "Items", "Skins", "RoundRules", "FurnitureSpecs", "MapLayout", "MapMarks", "MapThemes"]

PRELUDE = """
local __sources = {}
local __cache = {}
local __parent = setmetatable({}, { __index = function(_, name) return { __module = name } end })
local function require(target)
	local name = target.__module
	if __cache[name] == nil then
		local loader = __sources[name]
		assert(loader, "bundle has no module " .. tostring(name))
		__cache[name] = loader({ Parent = __parent, Name = name })
	end
	return __cache[name]
end
local script = { Parent = __parent, Name = "Main" }
"""


def module_source(name: str) -> str:
    text = (SHARED / f"{name}.luau").read_text()
    # `export type` is only legal at the top of a real module.
    text = re.sub(r"^export type ", "type ", text, flags=re.MULTILINE)
    text = text.replace("--!strict", "")
    return text


def bundle(main: str) -> str:
    parts = [PRELUDE]
    for name in PURE_MODULES:
        parts.append(f'__sources["{name}"] = function(script)\n{module_source(name)}\nend\n')
    parts.append(main)
    return "\n".join(parts)
