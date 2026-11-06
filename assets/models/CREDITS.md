# Model credits

All third-party models are CC0 from [Poly Haven](https://polyhaven.com), glTF with 1k textures.
The furniture/fittings set fetched by `tools/models/fetch_models.py` is listed in
[POLYHAVEN_CREDITS.md](POLYHAVEN_CREDITS.md). Everything else in `assets/models/*.glb` is our own
Blender kit (`tools/blender/build_props.py`).

## Set dressing (`scripts/world/decor.gd`)

| Folder | Poly Haven asset | Author |
| --- | --- | --- |
| `game_console/` | [gaming_console](https://polyhaven.com/a/gaming_console) | Sean Buckley |
| `gamepad/` | [gamepad](https://polyhaven.com/a/gamepad) | Josh Dean |
| `succulent/` | [potted_plant_04](https://polyhaven.com/a/potted_plant_04) | James Ray Cock |
| `spray_cleaner/` | [multi_cleaner_bottle](https://polyhaven.com/a/multi_cleaner_bottle) | James Ray Cock |
| `bleach/` | [bleach_bottle](https://polyhaven.com/a/bleach_bottle) | James Ray Cock |
| `cutting_board/` | [wooden_cutting_board](https://polyhaven.com/a/wooden_cutting_board) | Kuutti Siitonen |
| `notepads/` | [office_notepads](https://polyhaven.com/a/office_notepads) | Ulan Cabanilla |
| `stationery/` | [stationery_supplies](https://polyhaven.com/a/stationery_supplies) | Mateusz Sadek |
| `photo_frame/` | [standing_picture_frame_01](https://polyhaven.com/a/standing_picture_frame_01) | James Ray Cock |
| `hamper/` | [wicker_basket_01](https://polyhaven.com/a/wicker_basket_01) | Kuutti Siitonen |
| `clay_pot/` | [planter_pot_clay](https://polyhaven.com/a/planter_pot_clay) | Amal Kumar |
| `plunger/` | [plunger](https://polyhaven.com/a/plunger) | James Ray Cock |
| `binder/` | [binder_notebook](https://polyhaven.com/a/binder_notebook) | DaDrood |

Decor also reuses `cardboard_box/` and `broom/` from the list above. All other dressing (shoes,
clothes, bottles, cans, cup noodles, bento, garbage bags, rice cooker, rack, fan, calendars,
switch plates…) is built from primitives in `decor.gd`.
