"""Builds CommandBar.lua: one line of Luau that installs the game when pasted
into Roblox Studio's command bar. Run after editing anything in src/:

    python3 tools/make_command_bar.py
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (parent expression, script name, class, source file). Each parent is a folder
# the installer recreates, so re-running it replaces the old version.
SCRIPTS = [
    ("shared", "Config", "ModuleScript", "src/shared/Config.luau"),
    ("shared", "Words", "ModuleScript", "src/shared/Words.luau"),
    ("server", "GameServer", "Script", "src/server/GameServer.server.luau"),
    ("client", "Main", "LocalScript", "src/client/Main.client.luau"),
    ("client", "CanvasRenderer", "ModuleScript", "src/client/CanvasRenderer.luau"),
    ("client", "Theme", "ModuleScript", "src/client/Theme.luau"),
    ("client", "Sounds", "ModuleScript", "src/client/Sounds.luau"),
    ("client", "Ui", "ModuleScript", "src/client/Ui.luau"),
    ("client", "Effects", "ModuleScript", "src/client/Effects.luau"),
    ("client", "ColorPicker", "ModuleScript", "src/client/ColorPicker.luau"),
]


def luau_string(text: str) -> str:
    """A double-quoted Luau literal with no newlines and only ASCII characters,
    so it survives being pasted into a single-line box."""
    out = []
    for byte in text.encode("utf-8"):
        char = chr(byte)
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char == "\n":
            out.append("\\n")
        elif char == "\t":
            out.append("\\t")
        elif 32 <= byte < 127:
            out.append(char)
        else:
            out.append(f"\\{byte:03d}")
    return '"' + "".join(out) + '"'


def main() -> None:
    parts = [
        'local RS=game:GetService("ReplicatedStorage")',
        'local SSS=game:GetService("ServerScriptService")',
        'local SPS=game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")',
        "local function folder(parent,name)"
        " local old=parent:FindFirstChild(name) if old then old:Destroy() end"
        ' local f=Instance.new("Folder") f.Name=name f.Parent=parent return f end',
        "local function put(parent,name,class,source)"
        " local s=Instance.new(class) s.Name=name s.Source=source s.Parent=parent end",
        'local shared=folder(RS,"GuessAndDraw")',
        'local server=folder(SSS,"GuessAndDraw")',
        'local client=folder(SPS,"GuessAndDraw")',
    ]
    for parent, name, cls, path in SCRIPTS:
        source = (ROOT / path).read_text(encoding="utf-8")
        parts.append(f'put({parent},"{name}","{cls}",{luau_string(source)})')
    parts.append('print("Guess & Draw installed! Press Play to test.")')

    command = "; ".join(parts) + "\n"
    (ROOT / "CommandBar.lua").write_text(command, encoding="ascii")
    print(f"Wrote CommandBar.lua ({len(command):,} characters)")


if __name__ == "__main__":
    main()
