# UI redesign plan: "Office hours"

The UI should feel like the paperwork, signage and screens of a dull Tokyo
office worker's life: train-station signs, the evacuation map on the back of
the apartment door, a timecard, a business planner (techō), konbini receipts and
the NHK emergency banner. Day by day, the routine breaks down; the UI shows
that by going from tidy and grey to stamped, red and emergency-coloured.

Today everything is built in `scripts/ui/hud.gd`: Godot's default font, six colour
constants, dark rounded panels. It works, but it looks generic. Nothing in it says
Tokyo or salaryman.

## Principles

1. **Found objects, not game widgets.** Every screen should look like something
   that exists in his life, in this order of preference: a real object (timecard,
   techō, 回覧板 neighbourhood notice), then real signage (station signs, evacuation
   maps), then real screens (phone, NHK). A generic panel is the last resort.
2. **Bilingual like the signs.** English stays primary for gameplay text. Small
   Japanese labels sit above or before it, as on JR signs: 体調 HEALTH, 出入口 ENTRANCES.
   Only short, fixed labels get Japanese; story text stays English.
3. **Boring by day, alarming by night.** Day uses office greys, paper white and
   navy, low contrast and a quiet HUD. Night brings sign yellow, emergency red and
   ticker banners. The phase change alone should feel like a punch-out.
4. **Quiet HUD.** Hide what isn't needed right now: bars fade when full and
   unchanged, controls only show until first used, and the entrances map only
   shows at night or when damaged.
5. **Keep the hooks.** The smoke test uses `hud.overlay_kind`, `_start_run()`,
   `_close()` and `_restart()`. Keep those names.

## Visual language

**Type.** All fonts are OFL. Put them in `assets/fonts/`:
- **BIZ UDPGothic:** the UI face. Morisawa's universal-design font, used in Japanese
  government and office documents. Clean, a little bureaucratic, and has kana and kanji.
- **BIZ UDMincho:** printed documents such as notices, clue papers and the death notice.
- **DSEG7 Classic:** the 7-segment clock, like an alarm clock or station board.
- **A monospace face** (BIZ UDGothic, the fixed-width version): receipts, timecard
  punches and forum posts.

**Palette** (tokens in one place, `scripts/ui/ui_style.gd`):

| Token | Use | Value |
|---|---|---|
| `paper` | documents, cards | `#F2EFE6` |
| `ink` | text on paper | `#1E2226` |
| `office` | day panels (fluorescent grey) | `#2B2F33` @ 85% |
| `navy` | suit navy, headers | `#1F2A44` |
| `line_green` | "safe/good" (Yamanote line green) | `#80C241` |
| `sign_yellow` | warnings, station-sign yellow | `#F5C400` |
| `hanko` | stamps, accents | `#C8102E` |
| `alert_red` | emergency banners | `#D7000F` |
| `lcd` | phone/LCD glow | `#CFE8E3` |

**Shapes.** Square corners or a 2 px radius, like signs and forms. Thin 1 px rules,
form-field boxes, line-colour chips (the circle with a station number, e.g.
`JY 17`), and red hanko circles for confirmations.

**Theme.** Build one `Theme` in code (`ui_style.gd`, no `.tres`, matching the
project's build-in-code rule) and set it on the HUD root. Replace the `_label`
and `_button` per-node overrides with theme type variations: `Paper`, `Sign`,
`Ticker`, `Stamp`.

## Element by element

| Now | Becomes | Notes |
|---|---|---|
| Top-left stats panel | **Station clock + vitals strip** | 7-seg time with the date in Japanese format (`11月5日(水)`). Phase as a line chip: `DAY` grey, `NIGHT 1/5` red. Vitals become thin bars labelled `体調 HEALTH`, `空腹 HUNGER`, `水分 THIRST` that fade out when healthy. Inventory moves to a small receipt-style list that only shows on change or when holding Tab. |
| Warning lines (gas, water cutoff, forecast) | **Pinned memo slips** | Small yellow slips under the clock, one per warning, with a pin icon. The gas countdown slip blinks red. |
| Top-right entrances panel | **Evacuation map (避難経路図)** | A mini floor plan of the 1LDK, drawn like the green-and-white plan on the back of Japanese apartment doors, with a 現在地 YOU ARE HERE dot. Each entrance is an icon tinted green, yellow or red by HP, and flashes when hit. Shows at night or when damaged. The data already exists (barricades with position and hp). |
| Toasts | **Three channels** | Danger becomes an NHK-style red ticker (テロップ) across the top. Phone or story messages become LINE-like notification cards sliding in top-right. Thoughts and minor info become TV-caption subtitles bottom-centre (white text, black outline). Pick the channel by message kind and source. |
| *(unused)* `earthquake_warning` signal | **緊急地震速報 banner** | Full-width EEW banner with the chime already in `sfx`: "Strong shaking expected. 強い揺れに警戒". This is the highest-impact addition and costs very little. |
| Interaction prompt | **Sign plate** | Small dark plate under the crosshair: key cap `E`, the action, and `長押し HOLD` when needed. The hold progress becomes a ring around the key cap instead of a long bar. |
| Controls bar | **Contextual key caps** | Each hint shows until used about 3 times, then hides. The full list moves into the pause menu as the "取扱説明書 Manual" page. |
| Crosshair | Same, but dims when nothing is targeted and becomes a small ring on interactables. |  |
| *(none)* damage | **Hurt vignette + low-health desaturation** | Red edges on a bite, and the screen loses colour below 30% health. A shader on a full-screen ColorRect. |
| Intro card | **Phone lock screen at 07:58** | The phone fills the screen with missed calls and a J-ALERT push notification. The title `KEEP LIVING`, with `生きていく` under it, sits under the clock. Press E to "Get up". Past-life stats show as small lock-screen widgets. |
| Clue popup | **Per-source documents** | Phone becomes a LINE/J-ALERT screen. TV becomes an NHK frame with ticker. Laptop becomes a 2ch-style forum thread in mono. Radio becomes a transcript slip. Notices become a 回覧板 neighbourhood circular on paper with a hanko. Each clue carries a `source` in `scenario_*.gd` that picks the template. |
| Journal (J) | **Business planner (手帳)** | Weekly-planner spread: left page has clues as handwritten-style entries with taped edges, right page has Insights. "What is happening?" becomes an approval form (稟議書): pick a theory, then stamp your hanko to submit (one stamp per life). Echoes become business cards (名刺) in the back pocket. |
| Pause | **Planner cover** | Navy planner cover with tabs: Resume, Journal, Manual, Restart, Erase, Quit. "Erase all progress" becomes a shred action with confirmation. |
| Death + Echo choice | **Timecard punched out** | A timecard slides into a clock and stamps `退勤 21:53 OUT` in red. The cause is typed on the card. His name field is blurred (see Decisions). The Echo choice is three 名刺 business cards from past selves, with the name and company blurred and the Echo itself ("3rd life · Night 2 · *Prepared*…") sharp; click one to keep it. |
| Rescue / win | **Last train notice** | The station board shows "本日の運行は終了しました": service has ended for today, and so has the nightmare. Shows stats and "Live it again". |

## Build order

1. **Foundation** (small): fonts in `assets/fonts/`, plus `ui_style.gd` with the palette,
   theme and type variations. Restyle the existing widgets with it. No layout changes.
   Smoke test plus screenshots.
2. **High-impact additions** (small–medium): EEW banner, hurt vignette, ticker for
   danger messages, sign-plate prompt with hold ring, contextual controls.
3. **HUD layout** (medium): station clock and vitals strip, memo slips,
   evacuation-map entrances panel (draws from `apartment.barricades` positions).
4. **Screens** (medium–large): phone intro, per-source clue documents (adds `source`
   to clue data), timecard death and business-card Echoes, then the techō
   journal with the hanko theory form, and the planner pause.
5. **Polish:** slide and stamp tweens, `ui_click` / paper / stamp sounds (the clips
   already exist), 16:9 and 21:9 checks, and a 14 px minimum text size at 900p.

## Decisions

- **The protagonist stays anonymous.** Wherever his name, company or employee number
  would appear (the timecard, the business cards, the ID badge on the phone lock
  screen), it is blurred, like text you can't quite focus on. Build the field normally,
  then run it through a blur shader (or a pre-blurred texture) so the shape of the
  text is there but unreadable. Everything around it stays sharp: the `退勤 OUT`
  stamp, punch times, the death cause, and each Echo's title and description. On the
  business cards that means a blurred name and company over a sharp past-life line,
  e.g. `3rd life · Night 2 · Prepared`.

## Open questions

- How much Japanese? The plan uses short bilingual labels. A full JP locale is a
  separate project.
- Should the phone become a real in-world object you raise (diegetic), or stay a
  2D overlay for now? This plan assumes overlay.
