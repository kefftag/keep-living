# Keep Living: notes for Claude

Godot 4.4 GDScript first-person roguelite in a realistic Tokyo 1LDK. Design: `docs/GDD.md`. Art pipeline: `docs/BLENDER_PIPELINE.md`.

## Architecture
- No authored scenes besides `scenes/main.tscn`. `scripts/main.gd` builds the world in code.
- Autoloads: `Game` (`scripts/autoload/game_state.gd`, per-run state, wiped on death) and
  `Meta` (`scripts/autoload/meta_progress.gd`, persists: clues, Echoes, stats → `user://keep_living_meta.json`).
- Scripts reference each other with `preload` consts and duck typing. Avoid `class_name`
  (keeps headless runs working without an editor-generated class cache).
- Interactables extend `scripts/world/interactable.gd` and override
  `get_prompt/get_status/get_flag/get_duration/get_noise/perform`.
- Physics layers: 1 world (parsed by the navmesh), 2 barricades (NOT parsed, so the navmesh
  has a path through entrances), 3 zombies, 4 player, 5 interior doors (player only; zombies
  shove them open), 6 breached entrances (only the look-ray hits them).
  Zombies don't collide with each other.
- Coordinates: +X east, +Z south (corridor side), balcony at -Z. Interior x 0..6.37,
  z 0..7.28, 910 mm module, ceilings 2.4 m, genkan/corridor at y = -0.15.
- Realism is a goal: use real Japanese apartment dimensions and fittings. Zombie collision
  radius must equal the navmesh agent radius (0.2) or they snag on door frames.
- Scenario content is data in `scripts/data/scenario_*.gd`.

## Checks
Run the scripted playthrough after gameplay changes. It must print `SMOKE OK`:

```bash
godot --headless --path . --import
godot --headless --path . -- --smoke-test
```

Screenshots: `tools/dev/shots.sh /abs/dir` runs the smoke test in a real window **in the
background** (launched with `open -g`; the window can't take focus or catch clicks, the mouse is
never captured, and real input is ignored), so it doesn't disturb whoever is using the Mac. It
prints the result lines and saves `NN_name.png` plus `godot.log` in the directory. On Linux use
`--shots=/abs/dir` under `xvfb-run`.

## Art & sound
- Model lookup per prop name: `assets/models/<name>/<name>.gltf` (Poly Haven scan, fitted to the
  prop's box) → `assets/models/<name>.glb` (Blender kit, used as authored, `kl_*` materials get
  textured) → grey box. See `scripts/world/props.gd`.
- Surfaces: `Props.surface("floor_wood")` etc., triplanar PBR from `assets/textures/`.
- Sound: `Sfx.play(name, pos)` / `Sfx.loop_on(name, node)`; names map to `assets/audio/<name>[_N].wav`.
- Blender MCP setup and first prompts: `docs/BLENDER_MCP_SETUP.md`.

## Models
`assets/models/<name>.glb` replaces the grey box with the same name. Front = Blender −Y,
origin bottom-centre, metres, sizes from the table in `docs/BLENDER_PIPELINE.md`.
Regenerate the baseline kit with `tools/blender/build_props.py`.
