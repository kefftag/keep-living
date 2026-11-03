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

## The apartment (3F, 1LDK, ~40 m²)

| Area | Contents |
| --- | --- |
| Bedroom | futon bed (rest), **wardrobe** (hazard, falls onto the bed), phone (clue), drawers (loot), desk + laptop (clue) |
| LDK | kitchen cabinets, sink (water), **gas stove + main** (hazard/cooking), fridge (spoils after the power cut), **bookshelf** (hazard), TV (clue, needs power), kotatsu + hand-crank radio (clue at night), binoculars (clue by day) |
| Bath / toilet | **bathtub** (fill before day 2), medicine cabinet, toilet shelf |
| Closet | storage (materials), emergency bag (clue + supplies), toolbox |
| Genkan | shoe cabinet, mail slot (clues), **front door** |
| Outside | balcony (north) with partitions to the neighbours; shared outdoor corridor (south) to the stairwell |

**Entrances** (attacked at night):

| Entrance | Base HP | Approached from |
| --- | --- | --- |
| Front door (steel) | 300 | stairwell → corridor |
| Balcony door (glass) | 120 | neighbours' balconies |
| Bedroom window | 100 | neighbours' balconies |
| Bathroom window | 70 | stairwell → corridor |

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
- **Gas:** if the main is open when a quake hits, a leak starts. Close it within
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

## Scenarios (roadmap)
Each scenario reuses the apartment and systems but changes the threat, the
clue set, the hazards and the theory answer. Ideas to discuss:

- **Outbreak** (built): infected, sound-driven, nightly sieges.
- **Ash:** an eruption (Fuji?) or fallout. The threat is the *air*: seal gaps
  with tape, rationed filters, contaminated water, and looters at the door.
  Answer: radiation / eruption.
- **Static:** a signal from the sky. Screens and radios are dangerous to use,
  neighbours act strangely, and clues contradict each other.
- **Tide:** a flood or tsunami. The rising water makes the balcony and roof the
  goal, you move valuables upward, and the building groans.

## Open questions / next steps
- **Audio** is the biggest missing piece: knocking, groans, the early-warning
  chime, J-ALERT tone, rain. Much of the game is *hearing* the threat.
- Building exploration: the hallway, neighbour 302 (Tanaka), the stairwell,
  maybe a supply run that risks a day.
- The intercom: someone asks to be let in (sometimes it's a person).
- Pushing furniture to block doors, as a tradeoff against securing it.
- Camera: the current top-down cut-away suits planning. Consider a closer
  third-person or first-person mode for nights.
- Balance pass with real playtests (all tuning constants are at the top of
  their scripts).
