extends RefCounted
## The story layer shared by every scenario (docs/STORY.md): memory fragments
## (記憶) found in containers, clue sources and hidden spots, the recurring
## omens, pickup flavour for loot messages and the rescue closing lines.
##
## A fragment: {id, thread, title, text, source, min_lives, scenarios, key,
## understand}. `source` is a container id (loot_container.gd), a clue source
## node name (clue_source.gd) or a hidden spot id (keepsake.gd, SPOTS below).
## `min_lives` is compared with Meta.runs (the life being played, counted from
## 1). `scenarios` is "any" or an Array of scenario ids. `understand` is the
## extra line shown in the final scenario, Monday, when you know what it means.
##
## Texts may carry tokens filled from Meta: {lives}, {lives_minus_one},
## {deaths}, {last_cause}, {last_day}, {scenario}. See fill().

const THREADS := {
	"work": {"jp": "会社", "en": "Work"},
	"mother": {"jp": "母", "en": "Mother"},
	"body": {"jp": "体", "en": "Body"},
	"building": {"jp": "303号室", "en": "The building"},
	"hand": {"jp": "自分の字", "en": "Your handwriting"},
	"morning": {"jp": "07:58", "en": "Morning"},
}
const THREAD_ORDER := ["work", "mother", "body", "building", "hand", "morning"]

## The protagonist's name, wherever it would be printed or said: always a blur.
const NAME_BLUR := "……"

const FRAGMENTS := [
	# --- 会社 Work ---------------------------------------------------------------
	{"id": "payslip", "thread": "work", "title": "Payslip, September", "source": "bedroom_closet", "min_lives": 1,
		"scenarios": "any", "key": false,
		"text": "Base pay ¥268,000. Overtime allowance ¥0. A line printed in red: 固定残業代 (fixed overtime) 45h included.\n\nSomeone has written in pen beside it: 実際 142h (actually 142h).",
		"understand": "A hundred and forty-two hours. You used to think being tired was the same as being needed."},
	{"id": "badge", "thread": "work", "title": "ID card on a lanyard", "source": "shoe_cabinet", "min_lives": 1,
		"scenarios": "any", "key": true,
		"text": "Your employee card. The photo is you, nine years younger, smiling. The name printed under it is a smear, as if it got wet, though the card is dry.\n\n社員番号 0315.",
		"understand": "Nine years on that lanyard. It opened every door at the office and none of the ones in here."},
	{"id": "deck", "thread": "work", "title": "Laptop: 提案書_最終_v14.pptx", "source": "laptop", "min_lives": 1,
		"scenarios": "any", "key": true,
		"text": "Last saved 04:49. Slide 31 of 31 says 'Thank you!' in a font you hate. The title slide says Monday 28 October, 09:30.\n\nA sticky note on the bezel: 部長に見せる前に直す (fix before showing the boss).",
		"understand": "Nobody is going to see slide 31 at 09:30. The world will not end because of that."},
	{"id": "boss_line", "thread": "work", "title": "LINE: 課長", "source": "phone", "min_lives": 2,
		"scenarios": "any", "key": false,
		"text": "Sunday 23:12. 'Deck by 9. No excuses this time.'\nSunday 23:13. 'Also you're covering Kobayashi's accounts from Monday.'\nSunday 23:40. 'Read receipt on, I can see you're up.'",
		"understand": "He could see you were up. He never once asked why."},
	{"id": "resignation", "thread": "work", "title": "An envelope in the desk drawer", "source": "storage_closet", "min_lives": 3,
		"scenarios": "any", "key": false,
		"text": "退職届 (resignation letter), in careful handwriting. The date line is filled in: 28 October.\n\nIt's sealed, stamped with your hanko. The stamp is the only part of the name you can read, and it's just a red circle.",
		"understand": "You dated it today. Some part of you had already decided to live a different Monday."},
	{"id": "timecard", "thread": "work", "title": "Timecard, October", "source": "toolbox", "min_lives": 2,
		"scenarios": "any", "key": false,
		"text": "Punched in 08:51 every day. Punched out: 23:04, 23:47, 00:12, 22:58, 01:30…\n\nThe last line, Friday the 25th, has no 退勤 (clock-out) stamp at all.",
		"understand": "Friday has no clock-out stamp. In a way, you never left."},
	{"id": "mori_message", "thread": "work", "title": "Unsent message", "source": "phone", "min_lives": 4,
		"scenarios": "any", "key": true,
		"text": "To Mori, typed 04:51, never sent:\n\n'honestly i wish the world would just end so i don't have to present tomorrow lol'\n\nThe cursor is still blinking after 'lol'.",
		"understand": "You wished the world would end so Monday wouldn't come. It ended, again and again, and Monday is still here, waiting for you."},
	# --- 母 Mother ---------------------------------------------------------------
	{"id": "rice_bag", "thread": "mother", "title": "A 5 kg bag of rice", "source": "kitchen_cabinets", "min_lives": 1,
		"scenarios": "any", "key": false,
		"text": "新米 あきたこまち, Akita's new crop. On the tape, in your mother's square handwriting: ちゃんと食べてる? (Are you eating properly?)\n\nIt's unopened. The cup noodles beside it are not.",
		"understand": "She asks if you're eating because it's the one question you always answer."},
	{"id": "postcard", "thread": "mother", "title": "A postcard from Akita", "source": "vanity", "min_lives": 1,
		"scenarios": "any", "key": false,
		"text": "A photo of Lake Tazawa in autumn.\n\n'The maples are early this year. Your father would have liked them. Will you come for New Year? Call me when you can. Not too late, I go to bed at nine. 母'",
		"understand": "Call me when you can, she wrote. You still can."},
	{"id": "birthday", "thread": "mother", "title": "A gift, still wrapped", "source": "bedroom_closet", "min_lives": 2,
		"scenarios": "any", "key": false,
		"text": "A scarf from a department store, the bag still folded on top. The receipt is from three weeks ago.\n\nA card, unsigned: お誕生日おめでとう (Happy birthday). Her birthday was yesterday.",
		"understand": "You bought it three weeks early. You didn't forget her. You forgot yourself."},
	{"id": "missed_calls", "thread": "mother", "title": "Missed calls", "source": "phone", "min_lives": 1,
		"scenarios": "any", "key": true,
		"text": "母: 12 missed calls.\n\nFriday 19:02, Saturday 09:15, Saturday 20:30, Sunday 12:00, Sunday 21:47, Monday 05:52, 05:53, 05:55, 05:58, 06:10, 06:31, 07:40.\n\nThe ones on Monday are close together.",
		"understand": "The Monday calls are minutes apart. She never stopped trying to get through to you."},
	{"id": "voicemail", "thread": "mother", "title": "Voicemail, Monday 05:53", "source": "phone", "min_lives": 3,
		"scenarios": "any", "key": false,
		"text": "Mostly static. A woman's voice, older, very calm in the way people are calm when they aren't:\n\n'…can you hear me? I heard you on the phone. You weren't saying anything. Stay where you are. I've called them. They're coming. Stay—'\n\nIt cuts off.",
		"understand": "She heard you breathing from six hundred kilometres away, and she was the one who called for help."},
	{"id": "photo", "thread": "mother", "title": "A photo in a frame, face down", "source": "photo", "min_lives": 2,
		"scenarios": "any", "key": false,
		"text": "You, about eight, on a beach in Oga with a woman holding a watermelon. She is laughing at whoever is holding the camera.\n\nOn the back: 'You said you'd be a pilot.'",
		"understand": "You turned it face down so it wouldn't watch you work. She would rather you came home than flew."},
	# --- 体 Body -----------------------------------------------------------------
	{"id": "health_check", "thread": "body", "title": "Company health check, April", "source": "storage_closet", "min_lives": 2,
		"scenarios": "any", "key": true,
		"text": "健康診断 results. Most boxes are A. One is circled: 心電図 (ECG): D, 要精密検査 (needs detailed examination).\n\nA booking slip for a cardiology clinic is clipped to it, blank.",
		"understand": "Your heart told you in April. The booking slip has been blank ever since."},
	{"id": "energy_cans", "thread": "body", "title": "Energy drink cans", "source": "kitchen_cabinets", "min_lives": 1,
		"scenarios": "any", "key": false,
		"text": "Seven empty cans of the same brand, rinsed and stacked to go out on Wednesday.\n\nOn the side: 'Do not exceed 2 per day.'",
		"understand": "You rinsed them and stacked them neatly, so nobody would have to see how many there were. Not even you."},
	{"id": "pills", "thread": "body", "title": "A pharmacy bag", "source": "vanity", "min_lives": 2,
		"scenarios": "any", "key": false,
		"text": "From a drugstore, not a doctor: antacid, painkillers, an eye-drop bottle, and a box of 'heart and circulation' herbal tablets with three gone.",
		"understand": "You were trying to look after it, in the only way that didn't cost you a morning off."},
	{"id": "sleep_app", "thread": "body", "title": "Sleep tracker", "source": "phone", "min_lives": 3,
		"scenarios": "any", "key": false,
		"text": "Last 7 nights: 3h12, 4h01, 2h45, 3h30, 0h00, 5h10, 0h00.\n\nSunday night: tracking started 05:41. Heart rate graph: a jagged line, then flat. 'Sync error.'",
		"understand": "A jagged line, then flat. The phone didn't understand what it was recording. You do now."},
	{"id": "chest_note", "thread": "body", "title": "Notes app", "source": "laptop", "min_lives": 4,
		"scenarios": "any", "key": false,
		"text": "A note titled 'symptoms (for doctor?)':\n\n'tight chest when climbing stairs at Monzen-Nakacho'\n'left arm heavy on the train'\n'the thing where my heart skips'\n'sunday 05:38 it's doing it again'\n\nThat last line ends mid-word.",
		"understand": "You wrote it down instead of calling anyone. Then you lay down on the bed for a minute."},
	# --- 303号室 The building ----------------------------------------------------
	{"id": "manager_notice", "thread": "building", "title": "Notice from the management company", "source": "mail", "min_lives": 1,
		"scenarios": "any", "key": false,
		"text": "To the resident of 303: 'Your post has not been collected for some time. Please empty your box or contact us.'\n\nThe box number is right. The name on the label is the usual blur.",
		"understand": "To the building you were a box number that had stopped emptying. Someone still noticed."},
	{"id": "tanaka_complaint", "thread": "building", "title": "A note under the door", "source": "shoe_cabinet", "min_lives": 2,
		"scenarios": "any", "key": false,
		"text": "Small careful writing:\n\n'To 303. I don't mean to complain. I hear you typing at night, and sometimes something else. Are you all right? If you need anything I'm in 202. Tanaka.'",
		"understand": "A neighbour you've never spoken to asked if you were all right. Nobody at work ever did."},
	{"id": "siren_log", "thread": "building", "title": "Ward safety email", "source": "laptop", "min_lives": 3,
		"scenarios": "any", "key": false,
		"text": "Kōtō ward safety mail, 05:58: 'An ambulance is attending an emergency in your area. Please keep the corridor and stairwell clear.'\n\nYour building is the only one on the street with a stairwell.",
		"understand": "The siren that stops outside every morning. It has been waiting at the bottom of your stairs the whole time."},
	{"id": "delivery_slip", "thread": "building", "title": "不在票 (delivery notice)", "source": "mail", "min_lives": 2,
		"scenarios": "any", "key": false,
		"text": "'We called but you were out.' Sender: Akita. Contents: 食品 (food).\n\nAttempted: Saturday 10:12, Sunday 14:30. You were home both times.",
		"understand": "You were home both times, and you didn't open the door then either."},
	{"id": "door_marks", "thread": "building", "title": "Scratches on the inside of the front door", "source": "genkan_door", "min_lives": 5,
		"scenarios": "any", "key": true,
		"text": "Low on the door, at about the height of someone sitting on the genkan step, a tally scratched into the paint with a key.\n\nYou count. There are {lives_minus_one} marks. You don't remember making any of them.",
		"understand": "One mark for every morning you spent keeping this door shut. The people on the other side were never trying to hurt you."},
	# --- 自分の字 Your handwriting ------------------------------------------------
	{"id": "hand_first", "thread": "hand", "title": "A note taped inside the closet", "source": "bedroom_closet", "min_lives": 2,
		"scenarios": "any", "key": false,
		"text": "In your handwriting, which you'd know anywhere:\n\n'You've been here before. You won't believe this. Read it anyway.'",
		"understand": "You did read it. Every one of you did, every morning, and each of you left something for the next."},
	{"id": "hand_stove", "thread": "hand", "title": "A note in the toolbox", "source": "toolbox", "min_lives": 3,
		"scenarios": "any", "key": false,
		"text": "Your handwriting, hurried:\n\n'The way you died last time was {last_cause} Don't do that again.'\n\nThe ink is the same pen as on your desk.",
		"understand": "Every death had a different cause. Underneath, it was always the same one: a tight chest at 05:40, lying down for a minute."},
	{"id": "hand_count", "thread": "hand", "title": "Behind the breaker panel", "source": "breaker", "min_lives": 4,
		"scenarios": "any", "key": false,
		"text": "Your handwriting, smaller, steadier:\n\n'Morning number {lives}. Every time, the alarm says 07:58. Every time, something ends the world before nine. Have you noticed it's always before nine?'",
		"understand": "Always before nine. Always before the presentation. You asked for it at 04:51, and something listened."},
	{"id": "hand_door", "thread": "hand", "title": "Taped under the kotatsu", "source": "kotatsu", "min_lives": 6,
		"scenarios": "any", "key": false,
		"text": "Your handwriting:\n\n'The banging at the front door. It isn't them. Listen to it properly. Once, through the noise, I heard a voice say my name.'",
		"understand": "It was your name. Through the steel door, a stranger in orange has been saying it all morning."},
	{"id": "hand_last", "thread": "hand", "title": "Inside the toilet tank lid", "source": "toilet_shelf", "min_lives": 8,
		"scenarios": "any", "key": true,
		"text": "Your handwriting, very neat, the way you write when you're scared:\n\n'I think we're the ones keeping it shut. Next time it's Monday, a normal Monday, open the door.'",
		"understand": "It's Monday. A normal Monday. All you have to do is open the door."},
	{"id": "hand_tally", "thread": "hand", "title": "Pencil marks on the closet door frame", "source": "bedroom_closet", "min_lives": 10,
		"scenarios": "any", "key": false,
		"text": "Height marks, like a child's, but they're all at the same height, yours. Each has a date:\n\n28/10. 28/10. 28/10.\n\nToo many to count.",
		"understand": "You stopped growing on the 28th of October. You can start again on the 29th."},
	# --- 07:58 Morning -------------------------------------------------------------
	{"id": "wall_clock", "thread": "morning", "title": "The wall clock", "source": "wall_clock", "min_lives": 1,
		"scenarios": "any", "key": false,
		"text": "Battery-powered, Seiko. The hands say 07:58.\n\nThe second hand twitches and goes back, twitches and goes back.",
		"understand": "The clock isn't broken. It's waiting for you to let the morning go on."},
	{"id": "alarm", "thread": "morning", "title": "Phone alarms", "source": "phone", "min_lives": 1,
		"scenarios": "any", "key": false,
		"text": "06:30 アラーム (off)\n07:00 起きろ (wake up) (off)\n07:30 マジで起きろ (seriously wake up) (off)\n07:58 電車 08:14 (train 08:14) (ringing)",
		"understand": "The 08:14 train. You don't have to be on it."},
	{"id": "train", "thread": "morning", "title": "A commuter pass", "source": "shoe_cabinet", "min_lives": 3,
		"scenarios": "any", "key": false,
		"text": "Pasmo, Monzen-Nakacho to Ōtemachi, valid to 31 October. Last used Friday 23:51.\n\nIn your wallet behind it, folded small: the Tōzai line timetable with 08:14 circled twice.",
		"understand": "08:14, circled twice. There will be other trains."},
]

## Hidden spots (keepsake.gd). Positions in apartment coordinates; `size` is
## the look-ray box (physics layer 6 only, so nothing else collides with it).
## `look` is a short location for the journal and the popup.
const SPOTS := {
	"wall_clock": {"label": "Wall clock", "prompt": "Look closely at the wall clock", "look": "the wall clock",
		"pos": Vector3(2.835, 2.03, 1.8), "facing": PI * 0.5, "size": Vector3(0.36, 0.36, 0.08), "visual": "none"},
	"breaker": {"label": "Breaker panel", "prompt": "Look behind the breaker panel", "look": "behind the breaker panel",
		"pos": Vector3(2.83, 1.82, 5.05), "facing": PI * 0.5, "size": Vector3(0.42, 0.36, 0.1), "visual": "note_edge"},
	"kotatsu": {"label": "Kotatsu", "prompt": "Look under the kotatsu", "look": "under the kotatsu",
		"pos": Vector3(5.07, 0.0, 2.0), "facing": PI * 0.5, "size": Vector3(0.26, 0.12, 0.16), "visual": "note_floor"},
	"genkan_door": {"label": "Front door, inside", "prompt": "Look at the scratches low on the door", "look": "the inside of the front door",
		"pos": Vector3(3.46, -0.15 + 0.28, 7.155), "facing": PI, "size": Vector3(0.24, 0.24, 0.05), "visual": "scratches"},
	"photo": {"label": "Photo frame, face down", "prompt": "Turn the photo frame over", "look": "on the TV stand",
		"pos": Vector3(6.1, 0.45, 2.55), "facing": -PI * 0.5, "size": Vector3(0.14, 0.08, 0.2), "visual": "photo"},
}

## Where each source is, for the journal ("Found: ...").
const SOURCE_NAMES := {
	"bedroom_closet": "the bedroom closet", "shoe_cabinet": "the shoe cabinet", "storage_closet": "the storage shelves",
	"toolbox": "the toolbox", "kitchen_cabinets": "the kitchen cabinets", "vanity": "the washbasin cabinet",
	"toilet_shelf": "the toilet", "phone": "your phone", "laptop": "the laptop", "mail": "the post",
	"wall_clock": "the wall clock", "breaker": "behind the breaker panel", "kotatsu": "under the kotatsu",
	"genkan_door": "the front door", "photo": "the TV stand",
}

# --- Omens -------------------------------------------------------------------------
## story_director.gd fires each at most once per life, from life `from`.
const OMENS := [
	{"id": "siren", "from": 1, "when": "the first dawn",
		"text": "A siren. It stops right outside. Then nothing."},
	{"id": "clock", "from": 2, "when": "getting up after a rest",
		"text": "You get up. The wall clock says 07:58. Your phone says %s."},
	{"id": "knock", "from": 3, "when": "daytime",
		"text": "Three slow knocks at the front door. Through the peephole, the corridor is empty.",
		"after": "(Something about the knocking sounds like a fist, not a claw. Not a crowbar. A person's hand.)"},
	{"id": "radio", "from": 4, "when": "at night",
		"text": "Under the radio static: \"…sir? Sir, can you hear me? …breathing…\""},
	{"id": "call", "from": 5, "when": "daytime",
		"text": "Your phone lights up by itself: 母 calling.",
		"answer": "Static. Then one word, in her voice: \"…stay…\"",
		"missed": "The screen goes dark again. There's no missed call in the log."},
	{"id": "clear", "from": 7, "when": "on death", "text": "Clear!"},
]

# --- Rescue closing lines -----------------------------------------------------------
## [line, line once you hold at least KNOWING_KEYS key memories].
const KNOWING_KEYS := 3
const RESCUE_LINES := {
	"zombie": ["As the helicopter lifts, you look down at the city and every clock you can see says 07:58.",
		"As the helicopter lifts, someone in orange leans over you and shouts a question over the rotors. It sounds like a name. It sounds like yours."],
	"ash": ["Through the bus's taped-over windows, every station clock you pass says 07:58. Nobody else seems to notice.",
		"On the bus, someone holds a mask to your face and keeps saying, \"Stay with me.\" You weren't the one who was hurt. Were you?"],
	"tide": ["The boat turns out of your street. Behind you, through the rain, the clock by your bed glows 07:58 in the dark flat.",
		"A crew member wraps you in a foil blanket and presses two fingers to your neck. \"Pulse is weak,\" she says to someone. \"Keep him talking.\""],
}

# --- Monday ---------------------------------------------------------------------------
## The voice through the front door (subtitles and messages), in order, looping.
const MONDAY_VOICE := [
	"東京消防庁です. Tokyo Fire Department.",
	"Sir? Can you hear us? Your mother called us.",
	NAME_BLUR + "-san? " + NAME_BLUR + "-san, can you hear me?",
	"If you can't get up, knock on something. Anything. We're right here.",
	"We're not leaving. We just need the door open.",
]
const MONDAY_INTRO := "Monday, 28 October. 07:58.\n\nThe alarm. Sun through the balcony door. Birds. A train, far off.\n\nNothing is broken. Nothing is coming. The world, for once, has not ended.\n\nSomeone is knocking at the front door."
const MONDAY_SUIT := ["The suit. The lanyard. The bag.", "You open the door for the 08:14, and it opens on white.", "The alarm.", "07:58."]
const MONDAY_SUIT_LAST := "Again."
const MONDAY_DOOR := ["The latch. The chain. Daylight.", "Two paramedics in orange. One of them kneels beside you.",
	"White, and then a hospital ceiling."]
const MONDAY_MESSAGE := "Your phone, on the tray table, has one new message from 母:\n\n'I'm on the shinkansen. I'll be there by two. Don't you dare go to work.'"
const MONDAY_LAST := "You keep living."

# --- Pickup flavour -------------------------------------------------------------------
## container id -> loot kind -> objects. One is named in the loot message.
const PICKUP := {
	"kitchen_cabinets": {
		"food": ["the last cup noodle from a 12-pack bought at 02:00", "three packs of retort curry, the mild kind",
			"a bag of Akita rice, still taped shut", "a box of Calorie Mate, two bars left"],
		"water": ["two litres of Oi Ocha"],
	},
	"fridge": {
		"food": ["a bento from the konbini, discount sticker, two days old", "eggs, natto and half a tray of gyoza",
			"two onigiri from the konbini and a tub of kimchi"],
		"water": ["a carton of oolong tea", "two litres of Oi Ocha, one already opened"],
	},
	"emergency_bag": {
		"food": ["kanpan crackers in a tin, best before 2027", "alpha rice in foil packs, from the ward's disaster drill"],
		"water": ["six 500 ml bottles of five-year water", "a 2 L bottle of water with a drill sticker on it"],
		"masks": ["DS2 masks left over from the pandemic, a box of 20, 3 left"],
	},
	"bedroom_closet": {
		"medkits": ["a first-aid kit from the company's earthquake drill, never opened"],
		"materials": ["flattened Amazon boxes behind the suits", "a winter duvet in its zip bag, and the bag's cord"],
		"masks": ["a box of DS2 masks from the office stockroom"],
		"power_banks": ["a mobile battery from a trade fair, the company logo half peeled off"],
	},
	"vanity": {
		"medkits": ["plasters, gauze and a tube of Oronine in a drugstore pouch", "a first-aid kit, the seal unbroken"],
		"masks": ["a box of masks, 7 left, the ear loops tangled"],
	},
	"toilet_shelf": {
		"materials": ["a twelve-roll pack of toilet paper and a roll of packing tape"],
		"water": ["a 2 L bottle kept for flushing, still sealed"],
	},
	"storage_closet": {
		"materials": ["a stack of old 提案書 (proposal) printouts, double-sided", "flattened Amazon boxes and a roll of gaffer tape",
			"the leftover planks and bolts from a flat-pack shelf"],
	},
	"toolbox": {
		"materials": ["a hammer, a box of nails and the spare screws from the bed frame", "a cordless drill with a flat battery, and wood screws"],
	},
	"shoe_cabinet": {
		"materials": ["flattened Amazon boxes", "a broken vinyl umbrella, its ribs still good"],
	},
}
## Which loot kind the message names first.
const PICKUP_ORDER := ["masks", "medkits", "power_banks", "materials", "water", "food"]
const PICKUP_GENERIC := {
	"food": "something to eat", "water": "something to drink", "materials": "odds and ends you can build with",
	"medkits": "a first-aid kit", "masks": "dust masks", "power_banks": "a mobile battery",
}


# --- Lookups --------------------------------------------------------------------------

static func get_fragment(id: String) -> Dictionary:
	for f in FRAGMENTS:
		if f["id"] == id:
			return f
	return {}


static func in_thread(thread: String) -> Array:
	return FRAGMENTS.filter(func(f): return f["thread"] == thread)


static func key_ids() -> Array:
	var out: Array = []
	for f in FRAGMENTS:
		if f["key"]:
			out.append(f["id"])
	return out


static func known_keys() -> int:
	var n := 0
	for id in key_ids():
		if Meta.knows_memory(id):
			n += 1
	return n


static func is_handwriting(f: Dictionary) -> bool:
	return f.get("thread", "") == "hand"


static func thread_label(thread: String) -> String:
	var t: Dictionary = THREADS.get(thread, {"jp": "", "en": thread})
	return "%s %s" % [t["jp"], t["en"]]


## Can this fragment turn up in this life? Monday shows everything.
static func eligible(f: Dictionary, scenario_id: String) -> bool:
	if scenario_id == "monday":
		return true
	if Meta.runs < int(f["min_lives"]):
		return false
	var sc: Variant = f.get("scenarios", "any")
	if sc is String:
		return sc == "any" or sc == scenario_id
	return "any" in sc or scenario_id in sc


## The next fragment at `source` that isn't in `exclude` (seen this life).
## only_new: skip fragments already in Meta (containers and clue sources);
## hidden spots let you look again at a memory you already know.
static func next_at(source: String, scenario_id: String, exclude: Array, only_new: bool) -> String:
	for f in FRAGMENTS:
		if f["source"] != source or f["id"] in exclude:
			continue
		if not eligible(f, scenario_id):
			continue
		if only_new and scenario_id != "monday" and Meta.knows_memory(f["id"]):
			continue
		return f["id"]
	return ""


# --- Tokens ----------------------------------------------------------------------------

## Fill {lives}, {lives_minus_one}, {deaths}, {last_cause}, {last_day} and
## {scenario}. `lives_offset` 1 for text shown before the life starts (the
## intro card), when Meta.runs still counts the previous morning.
static func fill(text: String, lives_offset: int = 0) -> String:
	if not "{" in text:
		return text
	var lives: int = Meta.runs + lives_offset
	var ld: Dictionary = Meta.last_death
	var cause := str(ld.get("cause", ""))
	if cause == "":
		cause = "something you can't remember."
	else:
		cause = cause.substr(0, 1).to_lower() + cause.substr(1)
		if not (cause.ends_with(".") or cause.ends_with("!") or cause.ends_with("?")):
			cause += "."
	var day := int(ld.get("day", Meta.best_day))
	return text.format({
		"lives": lives,
		"lives_minus_one": maxi(0, lives - 1),
		"deaths": Meta.deaths,
		"last_cause": cause,
		"last_day": maxi(1, day),
		"scenario": Game.scenario.TITLE,
	})


static func text_of(id: String) -> String:
	return fill(str(get_fragment(id).get("text", "")))


# --- Pickup flavour ----------------------------------------------------------------------

## One line for a search: "Kitchen cabinets: the last cup noodle… (+3 food)".
## `parts` are the counted pickups ("+3 food"), `extras` the named ones
## ("a METAL BAT"); both may be empty (then "nothing useful").
static func loot_line(container_id: String, source_name: String, loot: Dictionary, parts: Array, extras: Array, rng: RandomNumberGenerator) -> String:
	if parts.is_empty() and extras.is_empty():
		return "%s: nothing useful." % source_name
	var kind := ""
	for k in PICKUP_ORDER:
		if int(loot.get(k, 0)) > 0:
			kind = k
			break
	var all: Array = parts + extras
	if kind == "":
		return "%s: found %s." % [source_name, ", ".join(all)]
	var pool: Array = PICKUP.get(container_id, {}).get(kind, [])
	var obj: String = pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else PICKUP_GENERIC.get(kind, "something")
	return "%s: %s (%s)" % [source_name, obj, ", ".join(all)]


static func rescue_line(scenario_id: String) -> String:
	var lines: Array = RESCUE_LINES.get(scenario_id, [])
	if lines.is_empty():
		return ""
	return lines[1] if known_keys() >= KNOWING_KEYS else lines[0]


static func omen(id: String) -> Dictionary:
	for o in OMENS:
		if o["id"] == id:
			return o
	return {}
