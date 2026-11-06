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
- **Tide** (built, below): unlocks after a rescue in Outbreak or Ash
  (`UNLOCK_AFTER_WIN` may be a list: any one of them opens it).
- **Static** shows locked on the scenario select ("unlocks after your first
  rescue in Outbreak").

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

### Tide (水害)
Typhoon No. 19, a super typhoon (超大型台風), comes ashore over Tokyo Bay at
high tide. The surge and a breached Arakawa levee flood Koto ward. The flat is
on the third floor, above the water, but the building is cut off. Survive 4
nights; SDF boats come at dawn on day 5. Core decisions: **protect the glass,
keep the phone alive, ration clean water, and decide who to let in.** All
numbers are constants at the top of `scripts/data/scenario_tide.gd`;
`scripts/systems/tide_director.gd` and `storm_guard.gd` run it.

- **Storm:** wind follows a curve (0..1): rising from 11:00 on day 1, peak
  23:00-04:00 on night 1, a lull on day 2, the back side (吹き返し, rolled
  ×0.75-1.0) on night 2, calm by 14:00 on day 3. The sky darkens with it (the
  environment rig's `storm` hook, beside Ash's `haze`), with sideways rain,
  tumbling debris past the balcony and a grey fog.
- **Debris:** 3 gusts per game hour at full wind, 8-16 damage × wind (×1.3 at
  night), aimed at the balcony door 1.5 : bedroom window 1.0 : bath window 0.2.
  The entrances are glass with their usual hp: E tapes an X across each pane
  (1 material, ×0.85 damage) then boards it with plywood (3 materials, ×0.2);
  patching gives +60 for 1 material. A window that blows in cuts anyone within
  3.2 m for 35 (×0.25 taped, 0 boarded; worse asleep), may soak a food, and lets
  the storm in (0.035 HP/min × wind per broken window, max 2) until boarded
  over (4 materials). Night 1 throws ~15 hits at the balcony door: bare or
  taped it blows in, boarded it needs a patch or two.
- **The balcony:** pots, a bucket and a drying rack sit outside. R at the
  balcony door brings them in; otherwise the first gust over 0.55 hurls them
  into the door (45 damage).
- **Power** dies at 18:00 on day 1 (the basement electrical room floods).
  **Tap water** runs brown at 06:00 on day 2: boil it at the sink (E, +2 water,
  twice a day) while the gas lasts, or drink it raw (R) and be sick for 12
  hours (0.06 HP/min). The **gas** meter trips some time on day 3. The bathtub
  holds 8 bottles if filled before the water turns.
- **Phone battery** (HUD bar): starts at 35%. R on the phone at the bedside
  plugs it in while the power lasts (+0.3%/min). Standby 0.01%/min, the phone
  light 0.1% per real second, each alert read 3%. Low Power Mode (insight)
  ×0.6, the solved theory ×0.7. The hand-crank charger (emergency bag, key 4 /
  D-pad left) gives +3% per turn for 2 thirst; a mobile battery (bedroom
  closet) adds 50% automatically at 10%. At night with no power and no light,
  actions take 1.6× as long. At 0% the light and the phone's alerts are gone.
- **Tanaka from 202** (the flat below: 3F is ours, so 2F is the one flooded)
  knocks on night 1 or 2 and waits 75 s. Answering the door opens a sign card
  with both choices and their costs. Let him in: +2 materials now, +1 each
  morning, his story (a clue), but −1 food and −1 water each morning. Keep the
  door shut: his note turns up under the door the next morning, and on the
  rescue boat nobody has seen him.
- **Signal:** with the signal insight, once the wind is under 0.35 (day 2
  afternoon to dawn day 4), R at the balcony door hangs a white sheet by day
  or flashes SOS with the phone light at night (10%): the boat comes at dawn
  on day 4 instead.
- **Clues:** the 警戒レベル5 緊急安全確保 area mail, the NHK typhoon broadcast
  (高潮特別警報), the 江東5区 hazard map on the fridge (ここにいてはダメです),
  the building notice about the basement electrical room and pumps, the
  Arakawa water level push on the phone, the ward typhoon leaflet, the view
  from the balcony, the NHK radio rescue broadcast, Tanaka's story or his note.
- **Insights:** storm forecast (wind now and the next peak), flood depth by
  floor, tap-water time, Prepared (bare glass, loose balcony things, unplugged
  phone flagged), Low Power Mode, where the wind hits (tonight's expected hits
  per window), boats at dawn day 5 (countdown), white cloth (the signal).
- **Theory:** "The water. A typhoon and a storm surge." Solved: the phone
  drains 30% slower.
- **Deaths:** flying glass (awake or asleep), exposure through a broken
  window, dysentery from raw tap water, dehydration (no bath filled),
  starvation (sharing with Tanaka has its own line).
- **Static:** a signal from the sky. Screens and radios are dangerous to use,
  neighbours act strangely, and clues contradict each other.

## Front end
Boot shows the title (生きていく / KEEP LIVING over the live apartment):
Continue / New life in the last scenario, Scenario select, Settings, Credits,
Quit. Settings persist in `user://settings.cfg` (`scripts/autoload/settings.gd`):
master / music-and-ambience / SFX volume, mouse sensitivity, gamepad look
speed, invert Y (mouse and stick), FOV,
fullscreen, 3D resolution scale, V-Sync, reduce camera shake, subtitles for
important sounds (with left / right / behind), large text. The pause menu has
Settings and "Title screen". After a death or rescue the next life starts on
the intro card; the title only comes back on boot or when asked for.

**Gamepad (Steam Deck).** Every action has a pad binding (`game_state.gd`):
left stick move, right stick look (with a response curve), A use, X second
action, RT swing, LB phone light, D-pad eat / drink / first aid / item, Y
journal, Start menu, B back, L3 toggles walking quietly. Every menu opens with
its first button focused, focus moves with the D-pad or left stick, the right
stick scrolls long pages, and B backs out wherever Esc does. Key caps (hints,
the prompt ring, button labels) show pad glyphs after any pad input and switch
back on keyboard or mouse input (`Game.glyph(action)`). On screens of 1366×820
or smaller (the Deck's 1280×800) the UI is laid out at 1280×800 and drawn 1:1
so text keeps its size, and the message column shrinks to fit between the
status panel and the entrances sign.

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
