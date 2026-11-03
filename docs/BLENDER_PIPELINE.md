# Blender → Godot pipeline

The game builds every prop as a grey box in code. When
`assets/models/<name>.glb` exists, that model is used instead
(`scripts/world/props.gd`). Art can therefore replace boxes one prop at a time,
and nothing breaks if a model is missing.

## Model contract

Every model, generated or hand-made, must follow these rules:

- **Units:** metres. Match the size in the table below, because collisions use
  the table's size, not the mesh.
- **Origin:** bottom-centre of the footprint (the object sits on z = 0).
- **Facing:** the *front* (drawer faces, screen, the side you use it from)
  points to **Blender −Y**. glTF export turns that into Godot +Z, which is what
  the game treats as "front". Tall furniture falls toward its front.
- **Export:** glTF binary (`.glb`), +Y up, apply modifiers, one prop per file,
  filename = model name.
- **Height cap for wall-side items:** walls are drawn sliced at **1.25 m** so
  the camera can see in. Anything much taller than that will poke out of the
  cut-away (tall furniture does, which is intentional: it's a hazard).
- Keep it low-poly with flat colours (materials → glTF base colour). No textures
  needed yet.

## Prop table

`W × H × D` = Blender `X × Z × Y`.

| Model name | W × H × D (m) | In game |
| --- | --- | --- |
| `bed` | 1.4 × 0.45 × 2.0 | futon bed (rest) |
| `wardrobe` | 1.0 × 1.9 × 0.6 | hazard, falls forward |
| `bookshelf` | 1.0 × 1.9 × 0.45 | hazard, falls forward |
| `side_table` | 0.4 × 0.45 × 0.4 | phone (clue) |
| `drawer_chest` | 1.0 × 0.9 × 0.5 | loot |
| `desk` | 0.9 × 0.72 × 0.55 | laptop (clue) |
| `kitchen_cabinet` | 1.0 × 0.9 × 0.55 | loot |
| `kitchen_sink` | 0.7 × 0.9 × 0.55 | water |
| `gas_stove` | 0.7 × 0.9 × 0.55 | gas main + cooking |
| `fridge` | 0.7 × 1.8 × 0.65 | loot (spoils) |
| `tv_stand` | 1.2 × 0.55 × 0.4 | TV (clue) |
| `kotatsu` | 0.9 × 0.4 × 0.9 | radio (clue) |
| `binocular_stand` | 0.4 × 0.6 × 0.4 | binoculars (clue) |
| `bathtub` | 1.6 × 0.55 × 0.75 | water storage |
| `medicine_cabinet` | 0.6 × 1.0 × 0.35 | loot |
| `toilet` | 0.45 × 0.8 × 0.7 | loot (shelf) |
| `storage_closet` | 1.2 × 1.6 × 0.5 | loot |
| `emergency_bag` | 0.45 × 0.35 × 0.3 | loot + clue |
| `toolbox` | 0.5 × 0.25 × 0.3 | loot |
| `shoe_cabinet` | 1.2 × 1.0 × 0.4 | loot |
| `mail_slot` | 0.35 × 1.0 × 0.12 | clues |
| `dining_chair` | 0.45 × 0.85 × 0.45 | decoration |
| `washing_machine` | 0.6 × 0.85 × 0.6 | decoration |
| `player` | ~0.5 × 1.6 × 0.3 | the survivor (the swing arm and bat are added in code) |
| `zombie` | ~0.5 × 1.7 × 0.3 | the infected |

The sizes live in `scripts/world/apartment.gd` (`_build_furniture`). Change both
places together.

## Option A: the generator script

`tools/blender/build_props.py` builds every prop above from boxes and cylinders
at exact size and exports them. It's the baseline art currently in
`assets/models/`.

```bash
blender -b --factory-startup -P tools/blender/build_props.py -- --out assets/models
```

Then open the project in Godot (it re-imports automatically) or run
`godot --headless --path . --import`.

## Option B: Blender MCP (iterating on art with Claude)

With the [blender-mcp](https://github.com/ahujasid/blender-mcp) addon running in
Blender and the MCP server connected to Claude (Claude Desktop or Claude Code
on your machine, since a cloud session can't reach your local Blender):

1. **Start from the kit.** Ask Claude to run `tools/blender/build_props.py` via
   `execute_blender_code` with `OUT_DIR` set to your absolute
   `assets/models` path and `EXPORT = False`. All the props appear in a row in
   the scene for you to look at.
2. **Iterate on one prop.** For example: *"Make the wardrobe look like a cheap
   flat-pack wardrobe: sliding doors, a slight overhang on top, keep it exactly
   1.0 × 1.9 × 0.6 m, origin bottom-centre, front facing −Y."* Claude can
   check its work with `get_viewport_screenshot`.
3. **Export.** *"Export the `wardrobe` object as assets/models/wardrobe.glb
   (glTF binary, selected only, +Y up)."* Godot picks it up on next focus.
4. **New props.** Add a builder to `build_props.py` (so it stays reproducible),
   add the row above, and place it in `apartment.gd`.

Asset sources (Poly Haven, Sketchfab, Hyper3D/Rodin via blender-mcp) are fine
as long as the result follows the contract. Check licences before committing.

## Not modelled (yet)
- **Entrances** (doors/windows) are drawn in code because they're sliced at the
  cut-away height and show damage, boards and breaches procedurally.
- **Walls/floors** are generated from the layout in `apartment.gd`. A future
  pass could export an `apartment_shell.glb` with proper door frames, skirting,
  tatami and tiles, with collision staying in code.
