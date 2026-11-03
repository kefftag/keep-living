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

`--shots=/abs/dir` (non-headless, e.g. under `xvfb-run`) saves screenshots.

## Models
`assets/models/<name>.glb` replaces the grey box with the same name. Front = Blender −Y,
origin bottom-centre, metres, sizes from the table in `docs/BLENDER_PIPELINE.md`.
Regenerate the baseline kit with `tools/blender/build_props.py`.
