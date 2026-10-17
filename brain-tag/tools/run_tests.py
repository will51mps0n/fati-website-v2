"""Run the logic tests in tests/*.spec.luau with the standalone Luau runtime.

Usage: python3 tools/run_tests.py [path/to/luau]
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from luau_bundle import ROOT, bundle  # noqa: E402

HARNESS = """
local __passed, __failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		__passed += 1
	else
		__failed += 1
		print("FAIL " .. name .. "\\n     " .. tostring(err))
	end
end
local testCase = test
local function expectEq(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end
local function expect(cond, label)
	if not cond then
		error(label or "expectation failed", 2)
	end
end
"""

FOOTER = """
print(string.format("%d passed, %d failed", __passed, __failed))
if __failed > 0 then
	error("tests failed")
end
"""


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau")
    if not luau:
        print("luau not found; pass its path as the first argument")
        return 2
    specs = sorted((ROOT / "tests").glob("*.spec.luau"))
    failures = 0
    for spec in specs:
        source = bundle(HARNESS + spec.read_text() + FOOTER)
        with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as handle:
            handle.write(source)
            path = handle.name
        result = subprocess.run([luau, path], capture_output=True, text=True)
        output = (result.stdout + result.stderr).strip()
        status = "ok" if result.returncode == 0 else "FAILED"
        print(f"== {spec.name}: {status}")
        if output:
            print(output)
        if result.returncode != 0:
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
