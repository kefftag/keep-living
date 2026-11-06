# Keep Living: Story bible

> The player should feel that something is wrong with the *morning*, not only with the
> world. Every scenario is a different end of the world, but it is always the same flat,
> the same Monday and the same 07:58. Nobody explains why. The objects in the flat do,
> slowly, if you look.

## The truth (never stated outright until the end)

- **Who and when.** You are an anonymous office worker, 32, living alone in room 303 of
  Maison Kirishima, a six-storey block in Kōtō ward. It is **Monday, 28 October**. The
  wall calendar has 〆切 (deadline) circled on the 28th.
- **Sunday night.** You worked through the night at the low table on the deck for
  Monday's 09:30 client presentation.
  - At **04:51** you typed a LINE message to your colleague Mori and never sent it:
    *"honestly i wish the world would just end so i don't have to present tomorrow lol"*.
  - At about **05:40** your chest went tight and your left arm went heavy. You lay down
    on the bed "for a minute".
- **The 07:58 alarm** is your second alarm, the one for the 08:14 train. It has been
  ringing ever since, because **this morning has not been allowed to finish.**
- **Every apocalypse is a version of that unsent message:** a world that ends so that
  Monday never comes. A sickness, ash, a flood: something always shuts the city down
  before 09:30.
- **The things at the door are trying to get in.** In every scenario the core verb is
  *keep them out*. The game's last turn is that you must **open the door**.
  - Your mother in Akita has called twelve times since Friday. Sunday was her birthday,
    and you forgot.
  - At 05:47 you called her by accident (a pocket dial), and she heard you struggling to
    breathe. She called 119 from Akita.
  - The banging on the front door is the paramedics.
- **The Echoes** (the perk you keep after each death) are what is left of each morning you
  didn't wake up from. The notes in **your own handwriting** hidden around the flat are
  from those mornings: past lives trying to leave you a way out.
- **The name** on the timecard, the business cards and the post is always a blur. You
  can't read your own name because you have stopped being anyone outside the job. The
  game never un-blurs it, not even at the end.

## Tone and rules

- Mystery first. Fragments hint and never explain. No fragment states "you are dying".
  The truth is assembled by the player, and confirmed only in the final scenario.
- **Everyday objects, quiet dread.** The horror is a 142-hour overtime sheet, a health
  check result never followed up, a voicemail from Mum. Written plainly, short, specific
  and Japanese-real.
- **Some fragments change with your history**: the loop count, deaths, how you last died.
  Tokens: `{lives}` (Meta.runs), `{deaths}`, `{last_cause}`, `{last_day}`, `{scenario}`.
- Every scenario carries the same recurring **omens** (below), so the mystery is felt
  even by players who never open the journal.

## Memories (記憶): collectible story fragments

- Found by **searching containers** (one per search, beside the loot), from **clue
  sources**, and in a few **hidden spots** that are new interactables.
- Persist forever (Meta), shared across all scenarios, and shown in the journal under
  記憶 Memories, grouped by thread.
- Each has `id, thread, title, source (where), min_lives (first life it can appear),
  scenarios ("any" or a list), key (needed for the ending)` and text.
- If a container's memory is already known, it offers the next unknown eligible one for
  that place.

### Threads
| Thread | JP | What it's really about |
|---|---|---|
| work | 会社 | the job that ate him |
| mother | 母 | the person still trying to reach him |
| body | 体 | the warnings he ignored |
| building | 303号室 | the outside world knocking |
| hand | 自分の字 | notes from his past lives |
| morning | 07:58 | the morning that won't end |

### Fragments

**会社 Work**
1. `payslip`, *Payslip, September* (bedroom_closet, life 1). "Base pay ¥268,000. Overtime allowance ¥0. A line printed in red: 固定残業代 (fixed overtime) 45h included. Someone has written in pen beside it: 実際 142h (actually 142h)."
2. `badge` (key), *ID card on a lanyard* (shoe_cabinet, life 1). "Your employee card. The photo is you, nine years younger, smiling. The name printed under it is a smear, as if it got wet, though the card is dry. 社員番号 0315."
3. `deck` (key), *Laptop: 提案書_最終_v14.pptx* (laptop clue source, life 1). "Last saved 04:49. Slide 31 of 31 says 'Thank you!' in a font you hate. The title slide says Monday 28 October, 09:30. A sticky note on the bezel: 部長に見せる前に直す (fix before showing the boss)."
4. `boss_line`, *LINE: 課長* (phone, life 2). "Sunday 23:12. 'Deck by 9. No excuses this time.' Sunday 23:13. 'Also you're covering Kobayashi's accounts from Monday.' Sunday 23:40. 'Read receipt on, I can see you're up.'"
5. `resignation`, *An envelope in the desk drawer* (storage_closet, life 3). "退職届 (resignation letter), in careful handwriting. The date line is filled in: 28 October. It's sealed, stamped with your hanko. The stamp is the only part of the name you can read, and it's just a red circle."
6. `timecard`, *Timecard, October* (toolbox, life 2). "Punched in 08:51 every day. Punched out: 23:04, 23:47, 00:12, 22:58, 01:30… The last line, Friday the 25th, has no 退勤 (clock-out) stamp at all."
7. `mori_message` (key), *Unsent message* (phone, life 4, any scenario). "To Mori, typed 04:51, never sent: 'honestly i wish the world would just end so i don't have to present tomorrow lol'. The cursor is still blinking after 'lol'."

**母 Mother**
1. `rice_bag`, *A 5 kg bag of rice* (kitchen_cabinets, life 1). "新米 あきたこまち, Akita's new crop. On the tape, in your mother's square handwriting: ちゃんと食べてる? (Are you eating properly?) It's unopened. The cup noodles beside it are not."
2. `postcard`, *A postcard from Akita* (vanity, life 1). "A photo of Lake Tazawa in autumn. 'The maples are early this year. Your father would have liked them. Will you come for New Year? Call me when you can. Not too late, I go to bed at nine. 母'"
3. `birthday`, *A gift, still wrapped* (bedroom_closet, life 2). "A scarf from a department store, the bag still folded on top. The receipt is from three weeks ago. A card, unsigned: お誕生日おめでとう (Happy birthday). Her birthday was yesterday."
4. `missed_calls` (key), *Missed calls* (phone, life 1). "母: 12 missed calls. Friday 19:02, Saturday 09:15, Saturday 20:30, Sunday 12:00, Sunday 21:47, Monday 05:52, 05:53, 05:55, 05:58, 06:10, 06:31, 07:40. The ones on Monday are close together."
5. `voicemail`, *Voicemail, Monday 05:53* (phone, life 3). "Mostly static. A woman's voice, older, very calm in the way people are calm when they aren't: '…can you hear me? I heard you on the phone. You weren't saying anything. Stay where you are. I've called them. They're coming. Stay—' It cuts off."
6. `photo`, *A photo in a frame, face down* (tv_stand/decor hidden spot, life 2). "You, about eight, on a beach in Oga with a woman holding a watermelon. She is laughing at whoever is holding the camera. On the back: 'You said you'd be a pilot.'"

**体 Body**
1. `health_check` (key), *Company health check, April* (storage_closet, life 2). "健康診断 results. Most boxes are A. One is circled: 心電図 (ECG): D, 要精密検査 (needs detailed examination). A booking slip for a cardiology clinic is clipped to it, blank."
2. `energy_cans`, *Energy drink cans* (kitchen_cabinets, life 1). "Seven empty cans of the same brand, rinsed and stacked to go out on Wednesday. On the side: 'Do not exceed 2 per day.'"
3. `pills`, *A pharmacy bag* (vanity, life 2). "From a drugstore, not a doctor: antacid, painkillers, an eye-drop bottle, and a box of 'heart and circulation' herbal tablets with three gone."
4. `sleep_app`, *Sleep tracker* (phone, life 3). "Last 7 nights: 3h12, 4h01, 2h45, 3h30, 0h00, 5h10, 0h00. Sunday night: tracking started 05:41. Heart rate graph: a jagged line, then flat. 'Sync error.'"
5. `chest_note`, *Notes app* (laptop, life 4). "A note titled 'symptoms (for doctor?)': 'tight chest when climbing stairs at Monzen-Nakacho', 'left arm heavy on the train', 'the thing where my heart skips', 'sunday 05:38 it's doing it again'. That last line ends mid-word."

**303号室 The building**
1. `manager_notice`, *Notice from the management company* (mail_pile, life 1). "To the resident of 303: 'Your post has not been collected for some time. Please empty your box or contact us.' The box number is right. The name on the label is the usual blur."
2. `tanaka_complaint`, *A note under the door* (shoe_cabinet, life 2). "Small careful writing: 'To 303. I don't mean to complain. I hear you typing at night, and sometimes something else. Are you all right? If you need anything I'm in 202. Tanaka.'"
3. `siren_log`, *Ward safety email* (laptop, life 3). "Kōtō ward safety mail, 05:58: 'An ambulance is attending an emergency in your area. Please keep the corridor and stairwell clear.' Your building is the only one on the street with a stairwell."
4. `delivery_slip`, *不在票 (delivery notice)* (mail_pile, life 2). "'We called but you were out.' Sender: Akita. Contents: 食品 (food). Attempted: Saturday 10:12, Sunday 14:30. You were home both times."
5. `door_marks` (key), *Scratches on the inside of the front door* (hidden spot: genkan door, life 5). "Low on the door, at about the height of someone sitting on the genkan step, a tally scratched into the paint with a key. You count. There are {lives_minus_one} marks. You don't remember making any of them."

**自分の字 Your handwriting** (notes from past lives; they appear only after deaths)
1. `hand_first`, *A note taped inside the closet* (bedroom_closet, life 2). "In your handwriting, which you'd know anywhere: 'You've been here before. You won't believe this. Read it anyway.'"
2. `hand_stove`, *A note in the toolbox* (toolbox, life 3). "Your handwriting, hurried: 'The way you died last time was {last_cause} Don't do that again.' The ink is the same pen as on your desk."
3. `hand_count`, *Behind the breaker panel* (hidden spot: breaker, life 4). "Your handwriting, smaller, steadier: 'Morning number {lives}. Every time, the alarm says 07:58. Every time, something ends the world before nine. Have you noticed it's always before nine?'"
4. `hand_door`, *Taped under the kotatsu* (hidden spot: kotatsu, life 6). "Your handwriting: 'The banging at the front door. It isn't them. Listen to it properly. Once, through the noise, I heard a voice say my name.'"
5. `hand_last` (key), *Inside the toilet tank lid* (toilet_shelf, life 8). "Your handwriting, very neat, the way you write when you're scared: 'I think we're the ones keeping it shut. Next time it's Monday, a normal Monday, open the door.'"
6. `hand_tally`, *Pencil marks on the closet door frame* (bedroom_closet, life 10). "Height marks, like a child's, but they're all at the same height, yours. Each has a date: 28/10. 28/10. 28/10. Too many to count."

**07:58 Morning**
1. `wall_clock`, *The wall clock* (hidden spot: wall clock, life 1). "Battery-powered, Seiko. The hands say 07:58. The second hand twitches and goes back, twitches and goes back."
2. `alarm`, *Phone alarms* (phone, life 1). "06:30 アラーム (off). 07:00 起きろ (wake up) (off). 07:30 マジで起きろ (seriously wake up) (off). 07:58 電車 08:14 (train 08:14) (ringing)."
3. `train`, *A commuter pass* (shoe_cabinet, life 3). "Pasmo, Monzen-Nakacho to Ōtemachi, valid to 31 October. Last used Friday 23:51. In your wallet behind it, folded small: the Tōzai line timetable with 08:14 circled twice."

## Omens: recurring strange things in every scenario
A small story director runs in every scenario. Each omen fires at most once per life,
and they escalate with `Meta.runs`. Each is a subtitle and/or message plus a sound
(mostly reusing existing sounds).

| From life | Omen |
|---|---|
| 1 | At dawn each day a siren approaches and **stops outside the building**. Nothing comes in. "A siren. It stops right outside. Then nothing." |
| 2 | While you rest on the bed, the wall clock reads 07:58 when you get up, whatever the real time. |
| 3 | Three slow knocks at the front door in daytime, even in Ash and Tide. Through the peephole the corridor is empty. "(Something about the knocking sounds like a fist, not a claw. Not a crowbar. A person's hand.)" |
| 4 | Under the radio static at night: "…sir? Sir, can you hear me? …breathing…" |
| 5 | The phone screen lights up by itself: 母 calling. If you answer (E on the phone within 10 s), static, then one word in her voice: "…stay…" |
| 7 | On death, before the screen, a beat of white light and a voice: "Clear!" |

## Endings

**Scenario rescues are partial endings.** Each rescue screen gets a closing line that
hints the rescue isn't real, e.g. Outbreak: "As the helicopter lifts, you look down at
the city and every clock you can see says 07:58." These change once the player has key
memories.

### The final scenario: 月曜日 Monday
- **Unlock:** rescued in at least 2 scenarios, AND at least 18 memories, AND all `key`
  memories (badge, deck, mori_message, missed_calls, health_check, door_marks, hand_last).
- **Title-screen nudge:** when it unlocks, the title screen shows: "A normal Monday."
- **The setting:** no apocalypse. 07:58, sun through the balcony door, birds, a train in
  the distance. Nothing is broken and no one is coming. The HUD is nearly empty: just the
  clock, which **does not move from 07:58**.
- **What you can do:** walk the flat. Every container and clue source shows its memory
  again, with a short new line because you understand now.
- **Something is wrong with you:** the screen edges darken and pulse slowly like a
  heartbeat. Walking is slower.
- **The front door:** from the start, someone knocks. A man's voice, calm, professional:
  "東京消防庁です. Tokyo Fire Department. Sir? Can you hear us? Your mother called us."
- **Two endings:**
  - **Put on the suit** (E at the closet): the suit, the lanyard, the bag. You go to the
    door to leave for the 08:14. The door opens on white. The alarm. 07:58. You wake up.
    *"Again."* This is the bad ending: no credits, back to the title, Monday still open.
  - **Open the door** (E on the front door, which every scenario taught you to
    barricade): the latch, the chain, daylight. Two paramedics in orange. One kneels.
    White fades to a hospital ceiling.
    - Text: "Your phone, on the tray table, has one new message from 母: 'I'm on the
      shinkansen. I'll be there by two. Don't you dare go to work.'"
    - Final line: **"You keep living."**
    - Credits roll over the empty flat, the lights going off room by room, the alarm
      clock finally showing 07:59.
- **After the true ending:** the title screen's flat is lit by morning sun and the wall
  clock shows the real time. All scenarios stay playable. Monday is marked 完 (finished).

## Pickup flavour
Ordinary loot messages get small, specific objects so every search says something about
him. Examples:
- food: "the last cup noodle from a 12-pack bought at 02:00", "a bento from the konbini,
  discount sticker, two days old", "a bag of Akita rice"
- water: "two litres of Oi Ocha", "a carton of oolong tea"
- materials: "flattened Amazon boxes", "a stack of old 提案書 (proposal) printouts,
  double-sided"
- first aid: "a first-aid kit from the company's earthquake drill, never opened"
- masks (Ash): "DS2 masks left over from the pandemic, a box of 20, 3 left"

Store these as per-container flavour lists in the story data.
