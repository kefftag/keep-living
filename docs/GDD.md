# Keep Living: Game Design

## Pitch

You are inside your apartment, somewhere in Tokyo. Something has happened
outside. You don't know what. Every life you get a little further: you make the
apartment safer, learn more about what's happening, and carry a small advantage
into the next attempt.

**Pillars**

1. **One room, deeply known.** The whole game is one 1LDK. Mastery is knowing
   every cupboard, weak point and hazard in it.
2. **Knowledge is the progression.** Clues persist through death and turn into
   mechanical *insights*. A veteran wins because they *know* things.
3. **The apartment can kill you too.** Zombies are only half the threat. An
   unsecured bookshelf, an open gas line or an empty bathtub will end a run
   just as surely.
4. **Grounded Tokyo.** J-ALERT, earthquake early warnings, tension poles
   (突っ張り棒), kick-through balcony partitions (蹴破り戸), filling the bathtub,
   a genkan, a kotatsu. Real disaster-prep details are the game mechanics.

## Core loop

```
07:58 wake ─► DAY (08:00-20:00)                 ─► NIGHT (20:00-06:00)         ─► next day ... night 5 survived ─► RESCUE
              scavenge, reinforce, secure,          infected attack entrances,
              read clues, fill tub, rest            noise draws more, breaches
                     │                                      │
                     └────────── death at any point ───────┘
                                      │
                         keep: clues/insights + choose 1 Echo
                                      │
                                  07:58 wake
```

- Clock: day runs at 3 game-min/s (~4 real minutes), night at 4 game-min/s
  (~2.5 real minutes). Holding an action doesn't stop the clock.
- Resting on the bed skips to 19:30 (+15 HP). Events in the skipped time
  still fire, and that's how the wardrobe gets you in your sleep.

## The apartment (3F, 1LDK, ~46 m²)

First person, as realistic as possible: a real Tokyo 1LDK floor plan on the
910 mm module (半間), 2.4 m ceilings, 85 cm kitchen counters, 70 cm interior
doors, a genkan one step (15 cm) below the hallway. Exact layout and sizes:
`scripts/world/apartment.gd`.

| Area | Contents |
| --- | --- |
| Genkan 玄関 | steel front door (outward-opening, peephole, door guard, mail slot), shoe cabinet, **mail on the floor** (clues), step up (上がり框) |
| Hallway | breaker panel; doors to the toilet, washroom and LDK; closet off the genkan (storage shelves, emergency bag, toolbox) |
| Toilet | separate WC with washlet, shelf above (loot) |
| Washroom 洗面所 | vanity with mirror cabinet (loot), top-loading washer on its pan, door to the unit bath |
| Unit bath | **bathtub** (fill it before day 2), barred frosted window onto the corridor |
| Kitchen | wall kitchen: cabinets (loot), sink (water), **2-burner gas stove + gas valve** (hazard / hot meals), fridge with microwave (spoils after the power cut), range hood |
| LDK | dining table, kotatsu + hand-crank radio (clue at night), TV (clue, needs power), desk + laptop (clue), binoculars (clue by day), **bookshelf** (hazard), wall AC, floor-to-ceiling sliding windows (掃き出し窓) |
| Bedroom 洋室 6畳 | bed (rest), **wardrobe** (hazard, falls across the bed head), phone on the bedside table (clue), built-in closet (loot), waist-height window, sliding doors (引き戸) to the LDK |
| Balcony | AC outdoor unit, laundry poles, kick-through emergency partitions (隔て板) with their warning sign |
| Outdoor corridor | railings, neighbour 304's door, our meter box (MB) in the alcove, stairwell at the east end |

Interior doors open and close. The infected shove closed doors open, so a
closed door doesn't stop them, but it does hide you and slow them.

**Entrances** (attacked at night):

| Entrance | Base HP | Approached from |
| --- | --- | --- |
| Front door (steel) | 300 | stairwell → corridor |
| Balcony door (glass) | 120 | neighbours' balconies |
| Bedroom window | 100 | neighbours' balconies |
| Bathroom window (barred) | 200 | stairwell → corridor |

Reinforce up to level 3: +100 HP per level, costs 2/3/4 materials. Patch to full
for 1 material. A breached entrance must be re-boarded (3 materials) with no
infected standing in it.

## Threats

### The infected (nights)
- Night *n* brings `2 + 2n` (4 on night 1, 12 on night 5). The targets are rolled
  each morning.
- They walk to an entrance and bash it (`2.5 + 0.6n` dmg/s, up to ×1.8 when
  there's noise nearby). When an entrance breaks they hunt you through the
  navmesh. Bites do 12 damage.
- **Noise** (footsteps, hammering, searching, swinging, falling furniture): if
  enough noise builds up near an entrance, up to 3 extra infected show up.
- At dawn the ones still outside wander off. Any that got in stay, slower by day.

### The apartment (any time)
- **Earthquakes:** day 1 afternoon (always), day 3 daytime, night 4. Unsecured
  tall furniture falls forward: 75 damage if you're in the way, fatal if you're
  asleep in its path.
- **Gas:** if the valve by the stove (ガス栓) is open when a quake hits, a leak starts. Close it within
  50 s or it explodes. Keeping the gas on lets you cook hot meals (+65 hunger
  instead of +35), so the risk buys you something.
- **Water:** the taps stop at 06:00 on day 2. A filled bathtub holds 8 bottles.
- **Power:** fails at 08:00 on day 3. Lights, TV and laptop go dead and the fridge spoils.
- **Hunger / thirst:** thirst empties in ~20 game hours, hunger in ~30. At zero
  you lose health.

## What persists through death

### 1. Knowledge (clues → insights)
Clues are found by interacting with sources. Some only appear at certain times.
Each clue stays in the journal forever, and most unlock an **insight**:

| Clue | Source / timing | Insight |
| --- | --- | --- |
| J-ALERT | phone, always | none (sets the tone) |
| Building notice | mail slot, day 1 | **The water will stop:** HUD warns before the taps run dry |
| Disaster-prep booklet | emergency bag | **Prepared:** unsecured furniture and open gas are flagged in the world |
| Emergency broadcast | TV, until the power fails | **Aftershocks:** 6 s early-warning chime before each quake |
| Looping radio message | radio, **night only** | **They hunt by sound:** noise meter, night hammering at half noise |
| View from the balcony | binoculars, **day only** | **They don't climb:** forecast of tonight's attacked entrances |
| Neighbour's note | mail slot, **day 2+** | **The bitten turn:** first aid heals +20 |
| Forum thread | laptop, **day 2 until the power fails** | **Rescue at dawn, day 6:** countdown on the HUD |

The timing gates push for more than one life: the radio needs you awake at
night, and the laptop needs you to survive to day 2 with power still on.

### 2. Theory board
With ≥3 clues known, the journal lets you name the apocalypse once per life:
*infection / something from the sky / radiation / civil unrest*. Guessing
right is permanent: +15% damage, "you know what you're fighting".
Future scenarios reuse the same board, so early clues are deliberately ambiguous.

### 3. Echoes (the small advantage)
Each death offers 3 Echoes you don't already own. You pick one. They are
permanent and stack.

| Echo | Effect |
| --- | --- |
| Hoarder's Memory | +3 starting materials |
| Pantry Sense | +2 food, +2 water |
| Steady Hands | actions 30% faster |
| Thick Skin | +25 max HP |
| Familiar Grip | start with the metal bat |
| Deep Breath | hunger/thirst drain 20% slower |
| Field Medic | start with a first-aid kit |
| Light Sleeper | resting fully heals; falling furniture never kills you in your sleep |

## Economy (scenario 1)
Materials available: 2 at start + ~10 looted + 2 per dismantled hazard (2 hazards).
Fully reinforcing all four entrances costs 36. You can't do everything, so
choosing what to fortify, what to dismantle and what to leave is the core
decision. The metal bat is hidden in one of three containers each run.

## Scenarios
Each scenario reuses the apartment and systems but changes the threat, the
clue set, the hazards and the theory answer.

**How it works.** `Game.scenario` is a script from `scripts/data/scenarios.gd`,
picked on the title screen or scenario select before a run, and remembered
(`Meta.last_scenario`). Everything scenario-specific is data on it: clues,
insights, theories, nights to survive, intro / night / dawn / rescue / death
text, the event timeline (`roll_events`), the tonight-plan, and `DIRECTORS`,
the systems `scripts/systems/scenario_world.gd` builds for the run. The same
file rewires the shared apartment through `CLUE_SOURCES` (what the phone, TV,
radio, laptop, mail and binoculars say) and `LOOT` (container contents), so
`apartment.gd` stays scenario-agnostic. A scenario with a different id from
the one the world was built for reloads the scene. Clues, theory, lives, best
day, rescues and last death are kept per scenario (`Meta.records`); Echoes are
shared. `UNLOCK_AFTER_WIN` gates a scenario behind a rescue in another one.

- **Outbreak** (built): infected, sound-driven, nightly sieges.
- **Ash** (built, below).
- **Static** and **Tide** show locked on the scenario select ("unlocks after
  your first rescue in Outbreak").

### Ash (降灰)
Mt Fuji erupts at 07:41 on day 1. Tokyo is 100 km downwind. Survive 5 days;
an evacuation bus comes at dawn on day 6. Core decisions move from
"reinforce" to **seal and ration**.

- **Ashfall** starts at 10:00 on day 1. Each day has a JMA-style forecast
  (少量 light 0.45 on day 1; days 2-4 a shuffle of 1.15 / 0.95 / 0.65; 0.35 on
  day 5). Ash depth and balcony load build with it.
- **Seal points:** the four entrances (same ids) plus the LDK and bedroom
  24-hour vents (給気口) and the range-hood duct. Leak weights: balcony door
  1.6, range hood 1.2, front door 1.0, LDK vent 1.0, bedroom window 0.9,
  bedroom vent 0.8, bath window 0.5 (7.0 total). E tapes a gap (1 material,
  ×0.35 leak), then plastic sheeting (2 materials, ×0.08). A smashed or forced
  opening leaks ×2.5 until boarded over (3 materials). Sealing everything
  fully costs 21 of the ~16 materials in a run.
- **Air:** indoor dust follows `d/dt = 0.16 · ashfall · leak − 0.012 · dust`.
  Below air quality 65, breathing costs up to 0.15 HP per game minute (scaled
  by how bad it is), also while resting. Unsealed on a heavy day the air
  settles around 25; everything taped once around 65.
- **Masks** (key 4): DS2 masks block 80% of the harm for 6 game hours. Found
  in the emergency bag (2), washbasin cabinet, bedroom closet.
- **Water** from the tap turns grey and undrinkable at 06:00 on day 2; fill
  the bath before. **Power** fails at 15:00 on day 2 (wet ash on the lines).
- **Balcony:** load grows with ashfall (×2.5 while it rains: 13:00-19:00 on
  day 3 or 4). At 100% the balcony door gives way (40 damage if you're near).
  R at the balcony door shovels it clear, but peels a level of tape and lets
  ash in (wear a mask).
- **Tremors** (day 1 afternoon, day 3, night 4) topple furniture and gas as
  in Outbreak, and shake tape loose from 1-2 seals.
- **Looters** on two nights (one of 2-3, one of 4-5), after midnight: they
  work a bar into the front door for 60 s at 3 + 0.8·night damage/s. R:
  brace the door (+100, 2/3/4 materials) by day; shout at them during an
  attempt (75% they leave with the bat, 30% without, otherwise they push
  harder). A forced door costs half your supplies (a quarter with the bat)
  and 35 HP (15).
- **Clues:** J-ALERT eruption push, NHK broadcast with the 噴火警戒レベル5
  banner and ticker, building management notice about the roof water tank,
  ward ashfall leaflet, looping radio on wet ash, the view from the balcony,
  Tanaka's note about looters, a Lawson receipt, the ward evacuation page.
- **Insights:** ash forecast, tap-water time, Prepared (gaps flagged), rain
  time + balcony load, per-gap leak readout, looter nights, the konbini bag
  (+2 masks, +1 material each life), evacuation-bus countdown.
- **Theory:** "The mountain. Fuji has erupted." Solved: masks last 50% longer.
- **Deaths:** ash in the lungs (unsealed / in your sleep), looters, the
  balcony door, dehydration (the grey tap), starvation.
- **Static:** a signal from the sky. Screens and radios are dangerous to use,
  neighbours act strangely, and clues contradict each other.
- **Tide:** a flood or tsunami. The rising water makes the balcony and roof the
  goal, you move valuables upward, and the building groans.

## Front end
Boot shows the title (生きていく / KEEP LIVING over the live apartment):
Continue / New life in the last scenario, Scenario select, Settings, Credits,
Quit. Settings persist in `user://settings.cfg` (`scripts/autoload/settings.gd`):
master / music-and-ambience / SFX volume, mouse sensitivity, invert Y, FOV,
fullscreen, 3D resolution scale, V-Sync, reduce camera shake, subtitles for
important sounds (with left / right / behind), large text. The pause menu has
Settings and "Title screen". After a death or rescue the next life starts on
the intro card; the title only comes back on boot or when asked for.

## Open questions / next steps
- **Audio** is the biggest missing piece: knocking, groans, the early-warning
  chime, J-ALERT tone, rain. Much of the game is *hearing* the threat.
- Building exploration: the hallway, neighbour 302 (Tanaka), the stairwell,
  maybe a supply run that risks a day.
- The intercom: someone asks to be let in (sometimes it's a person).
- Pushing furniture to block doors, as a tradeoff against securing it.
- An `apartment_shell.glb` from Blender (frames, wallpaper, flooring, tiles,
  switches, sockets) is the biggest realism upgrade left.
- Japanese gas meters (マイコンメーター) cut the gas automatically in a strong
  quake. Resetting it from the meter box in the corridor could be a risky
  daytime errand that brings back hot meals.
- Balance pass with real playtests (all tuning constants are at the top of
  their scripts).
