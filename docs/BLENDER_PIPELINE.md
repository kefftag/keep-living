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
- **It's seen up close in first person.** Detail matters at eye level (1.55 m):
  handles, seams, switches, labels. Textures and bevels are welcome now; keep
  each prop reasonable (a few thousand tris) and the .glb under ~2 MB.

## Prop table

`W × H × D` = Blender `X × Z × Y`. Sizes follow real Japanese fittings
(85 cm kitchen counters, a semi-double bed, a 1216-ish unit bath).

| Model name | W × H × D (m) | In game |
| --- | --- | --- |
| `bed` | 1.2 × 0.45 × 1.95 | bed (rest). Head end is the back (+Y) |
| `wardrobe` | 0.75 × 1.8 × 0.55 | hazard, falls forward across the bed head |
| `bookshelf` | 0.8 × 1.8 × 0.3 | hazard, falls forward |
| `side_table` | 0.4 × 0.45 × 0.4 | phone (clue) |
| `closet_builtin` | 1.8 × 2.0 × 0.55 | クローゼット, loot |
| `desk` | 0.85 × 0.72 × 0.5 | laptop (clue) |
| `kitchen_cabinet` | 0.6 × 0.85 × 0.65 | loot |
| `kitchen_sink` | 0.7 × 0.85 × 0.65 | water |
| `gas_stove` | 0.65 × 0.85 × 0.65 | gas cock + cooking |
| `fridge` | 0.6 × 1.6 × 0.62 | loot (spoils), microwave on top |
| `tv_stand` | 1.2 × 0.45 × 0.4 | TV (clue) |
| `kotatsu` | 0.8 × 0.4 × 0.8 | hand-crank radio (clue) |
| `binocular_stand` | 0.4 × 0.6 × 0.4 | binoculars (clue) |
| `vanity` | 0.75 × 1.8 × 0.5 | 洗面化粧台, loot |
| `washing_machine` | 0.6 × 1.0 × 0.6 | top-loader on its pan (decor) |
| `bathtub` | 1.7 × 0.55 × 0.7 | water storage |
| `toilet` | 0.45 × 0.8 × 0.7 | loot (shelf above) |
| `storage_shelf` | 0.8 × 1.8 × 0.35 | loot |
| `emergency_bag` | 0.45 × 0.35 × 0.3 | loot + clue |
| `toolbox` | 0.4 × 0.22 × 0.25 | loot |
| `shoe_cabinet` | 0.75 × 0.9 × 0.35 | 下駄箱, loot |
| `mail_pile` | 0.3 × 0.04 × 0.22 | mail through the door slot (clues) |
| `dining_table` | 0.75 × 0.7 × 0.75 | decor |
| `dining_chair` | 0.42 × 0.85 × 0.42 | decor |
| `range_hood` | 0.65 × 0.45 × 0.5 | decor, wall-mounted at 1.85 m |
| `wall_cabinet` | 1.3 × 0.6 × 0.35 | decor, wall-mounted at 1.6 m |
| `ac_indoor` | 0.8 × 0.28 × 0.25 | decor, wall-mounted at 2.08 m |
| `ac_outdoor` | 0.7 × 0.55 × 0.28 | decor, on the balcony |
| `curtain` | 0.35 × 2.0 × 0.08 | decor |
| `intercom` | 0.18 × 0.13 × 0.04 | decor, wall-mounted at 1.35 m |
| `breaker_panel` | 0.35 × 0.3 × 0.1 | decor, wall-mounted at 1.85 m |
| `zombie` | ~0.5 × 1.7 × 0.3 | the infected (collision radius 0.2 m) |

Interior doors take a model too: the door's `model_name` (unset by default) at
`width × (2.0 − floor) × 0.035`, with the origin at the bottom-centre of the leaf.

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
- **Entrances** (front door, windows) are drawn in code because they show
  damage, boards and breaches procedurally.
- **Walls/floors/ceiling** are generated from the floor plan in `apartment.gd`
  (910 mm module, 2.4 m ceilings). The biggest realism win now is an
  `apartment_shell.glb` from Blender: door frames (枠), wallpaper texture,
  flooring planks, genkan tile, unit-bath panels, switches and sockets, with
  collision staying in code. Build it on the same coordinates
  (Godot +X = Blender +X, Godot +Z = Blender −Y, origin at the interior's
  north-west corner).
