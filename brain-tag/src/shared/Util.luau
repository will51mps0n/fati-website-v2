-- Small helpers shared by server and client.

local Util = {}

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Unit vector on the ground plane, or nil when there is no horizontal part.
function Util.flatUnit(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return nil
	end
	return f.Unit
end

function Util.flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Util.color(hex: string): Color3
	return Color3.fromHex(hex)
end

-- 6729 -> "6,729"
function Util.commas(n: number): string
	local s = tostring(math.floor(n))
	local sign = ""
	if string.sub(s, 1, 1) == "-" then
		sign, s = "-", string.sub(s, 2)
	end
	local out = s
	while true do
		local replaced, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return sign .. out
end

-- 151 -> "2:31"
function Util.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Util
