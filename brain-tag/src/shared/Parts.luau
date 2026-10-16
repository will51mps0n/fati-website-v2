-- Part factory with Brain Tag's flat cartoon defaults: SmoothPlastic, no
-- shadows, smooth surfaces, anchored unless told otherwise.

export type PartProps = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: string | Color3,
	shape: Enum.PartType?,
	material: Enum.Material?,
	anchored: boolean?,
	canCollide: boolean?,
	canQuery: boolean?,
	transparency: number?,
	parent: Instance?,
}

local Parts = {}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z

Parts.UPRIGHT = UPRIGHT
Parts.ALONG_Z = ALONG_Z

local function toColor(c: string | Color3): Color3
	if typeof(c) == "Color3" then
		return c
	end
	return Color3.fromHex(c :: string)
end

function Parts.make(props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.name or "Part"
	part.Shape = props.shape or Enum.PartType.Block
	part.Size = props.size
	part.CFrame = props.cframe
	part.Color = toColor(props.color)
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Anchored = props.anchored ~= false
	part.CanCollide = props.canCollide ~= false
	part.CanQuery = props.canQuery ~= false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = props.transparency or 0
	if props.parent then
		part.Parent = props.parent
	end
	return part
end

-- An upright cylinder, which reads as a circle from the top-down camera.
-- `center` is the middle of the cylinder.
function Parts.disc(
	name: string,
	center: Vector3,
	diameter: number,
	height: number,
	color: string | Color3,
	parent: Instance?
): Part
	return Parts.make({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = CFrame.new(center) * UPRIGHT,
		color = color,
		parent = parent,
	})
end

-- A flat slab covering a map rectangle, with its top surface at `topY`.
function Parts.slab(
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	topY: number,
	thickness: number,
	color: string | Color3,
	parent: Instance?
): Part
	return Parts.make({
		name = name,
		size = Vector3.new(x2 - x1, thickness, z2 - z1),
		cframe = CFrame.new((x1 + x2) / 2, topY - thickness / 2, (z1 + z2) / 2),
		color = color,
		parent = parent,
	})
end

-- Turns a part into a weightless, non-colliding decoration of an assembly.
function Parts.makeVisual(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

-- Welds `part` to `base` at its current relative placement.
function Parts.weldInPlace(base: BasePart, part: BasePart): Weld
	local weld = Instance.new("Weld")
	weld.Name = "Weld"
	weld.Part0 = base
	weld.Part1 = part
	weld.C0 = base.CFrame:ToObjectSpace(part.CFrame)
	weld.Parent = part
	return weld
end

return Parts
