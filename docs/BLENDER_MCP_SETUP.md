# Setting up Blender MCP for Keep Living

Blender MCP lets Claude drive Blender directly: build and edit models, pull
assets from Poly Haven / Sketchfab, generate models from text with Hyper3D
Rodin, take viewport screenshots, and export straight into this repo.

It runs **on your own computer** (Blender is a desktop app), so use Claude
Code in a terminal on that machine, or the Claude Desktop app. A cloud
session can't reach your local Blender.

## 1. Install the tools

- Blender 4.2 or newer: <https://www.blender.org/download/>
- Godot 4.4 or newer (to play the game): <https://godotengine.org/download>
- `uv` (runs the MCP server):

```bash
brew install uv
```

On Windows use `winget install --id=astral-sh.uv -e`. On Linux use
`curl -LsSf https://astral.sh/uv/install.sh | sh`.

- Claude Code: <https://claude.com/claude-code>

## 2. Install the Blender add-on

```bash
uvx mcp-for-blender install-addon
```

Then in Blender: **Edit → Preferences → Add-ons**, search for "MCP" and tick
**Interface: MCP for Blender**. If it isn't listed, restart Blender, or click
**Install…** and pick the `addon.py` from
<https://github.com/ahujasid/blender-mcp>.

## 3. Start it inside Blender

In the 3D viewport press **N**, open the **MCP for Blender** tab, and click
**Start MCP Server** and then **Connect to Claude**. While you're there,
optionally tick **Poly Haven** (free CC0 assets), **Sketchfab** (huge model
library; needs a free API key) and **Hyper3D Rodin** (text/image → 3D model;
has a free trial key).

## 4. Connect Claude Code to it

In a terminal, inside your clone of this repo:

```bash
git clone https://github.com/kefftag/keep-living.git
```

```bash
cd keep-living
```

```bash
claude mcp add blender uvx mcp-for-blender
```

```bash
claude
```

Check it's connected by typing `/mcp` in Claude Code; `blender` should show
as connected. (Claude Desktop instead: Settings → Developer → Edit Config,
add `{"mcpServers": {"blender": {"command": "uvx", "args": ["mcp-for-blender"]}}}`,
then fully quit and reopen the app.)

**Cautions**
- Save your .blend first. Claude can run any Python inside Blender.
- Only connect one client at a time.
- Keep the add-on's port (9876) on your machine. It has no password.
- Anonymous usage stats are on by default. Set `DISABLE_TELEMETRY=true` to turn them off.

## 5. First jobs worth doing

Paste these into Claude Code once it's connected. Each one follows the rules
in `docs/BLENDER_PIPELINE.md` (metres, origin at the bottom-centre, front
facing Blender −Y, export to `assets/models/`).

**A terrifying zombie**

> Read docs/BLENDER_PIPELINE.md. Make the `zombie` model for Keep Living, a
> realistic horror game set in Tokyo. I want a recently turned office worker:
> gaunt, grey-green mottled skin, sunken milky eyes, a torn white shirt and
> loosened tie soaked in dried blood, a bite wound on the neck, slack jaw.
> Try Hyper3D Rodin first for the base mesh, otherwise Sketchfab
> (downloadable, CC-BY or CC0 only, and note the credit). Rig it with an
> armature, and add `walk` (slow, dragging one foot), `lunge`, `bash`
> (pounding on a door with both fists) and `idle` (swaying, head twitching)
> actions. 1.7 m tall, origin at the feet, facing −Y. Export to
> assets/models/zombie.glb with the animations, then screenshot the
> viewport so I can see it.

**The apartment shell**

> Using the floor plan in scripts/world/apartment.gd, model
> `apartment_shell.glb`: walls with door frames, white embossed wallpaper,
> oak flooring, the genkan tile and step, the unit-bath panels, light
> switches and sockets, curtain rails, the ceiling lights. Godot +X =
> Blender +X, Godot +Z = Blender −Y, origin at the interior's north-west
> corner (x 0, z 0) at floor level. Visual only; collision stays in code.

**Better hero props**: the bed, wardrobe, kitchen, fridge, front door and
bathtub, using Poly Haven / Sketchfab where possible.

After any export, open the project in Godot. It re-imports on focus. Then
run the check:

```bash
godot --headless --path . -- --smoke-test
```
