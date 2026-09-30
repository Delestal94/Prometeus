class_name NewsDesk
extends RefCounted
## The newsroom of the next-day newspaper (N-606.2, docs/diario-final.md).
## Pure and deterministic: the same facts and the same seed always make the
## same paper, and nothing here touches the tree, the autoloads or the
## network. RunChronicle gathers the facts and relays what compose() returns;
## NewsDesk.read() turns one entry into text on each peer, in its language.
##
## A fact is {kind, house (0-based, -1 none), tags, peer}. The catalogue
## (data/newspaper/stories.json) says, for each kind of fact, its section, how
## much of a headline it is (weight), its topic (one story per topic, so a
## broken mirror and its repair don't make two stories) and 3+ variants of
## headline and body, some only for a kind of box ("hen", "cake", a trap id...).
##
## What travels is the paper: {v, town, seed, front, stories, filler}, each
## entry {id, variant, slots}. Slots are the values the text fills in
## ({town}, {house}, {neighbor}, {player}, {km}, {minutes}, {count}); a slot
## that is a line to translate (a funny nickname) is a LocText array.

const CATALOG_PATH: String = "res://data/newspaper/stories.json"
const NICKNAME = preload("res://scripts/core/nickname.gd")
const LOC_TEXT = preload("res://modules/loc_text/loc_text.gd")
const FORMAT_VERSION: int = 1
## Stories under the front page: at most this many, and at least MIN_SECONDARY
## when the run gave that much news, from different sections first.
const MAX_SECONDARY: int = 3
const MIN_SECONDARY: int = 2
## Every {slot} a text may use.
const SLOT_NAMES: Array[String] = ["town", "house", "neighbor", "player", "km", "minutes", "count"]
## A variant for a kind of box is preferred this often over a generic one.
const TAGGED_CHANCE: float = 0.65
const MAX_SLOT_TEXT: int = 40

static var _catalog: Dictionary = {}


static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		_catalog = parsed if parsed is Dictionary else {}
	return _catalog


static func stories() -> Dictionary:
	return catalog().get("stories", {})


## The paper for these facts. `context`: seed (int), town, crew (an array of
## {peer, nick}), km (float), minutes (int), endless (bool), previous (kind ->
## variant the last paper used, which this one avoids repeating).
static func compose(facts: Array, context: Dictionary) -> Dictionary:
	var table: Dictionary = stories()
	var seed_value: int = int(context.get("seed", 0))
	var previous: Dictionary = context.get("previous", {})
	var by_kind: Dictionary = {}
	for fact: Variant in facts:
		if fact is not Dictionary:
			continue
		var kind: String = String((fact as Dictionary).get("kind", ""))
		if not table.has(kind) or bool(table[kind].get("filler", false)):
			continue
		if not by_kind.has(kind):
			by_kind[kind] = []
		(by_kind[kind] as Array).append(fact)
	# A run with nothing to tell is news too: the scandal of everything arriving.
	var has_news: bool = false
	for kind: String in by_kind:
		has_news = has_news or not bool(table[kind].get("neutral", false))
	if not has_news and not bool(context.get("endless", false)) and not by_kind.has("clean_run") \
			and table.has("clean_run"):
		by_kind["clean_run"] = [{"kind": "clean_run", "house": -1, "tags": [], "peer": 0}]

	var ranked: Array = _ranked(by_kind, table, seed_value)
	var used_players: Array = []
	var paper: Dictionary = {"v": FORMAT_VERSION, "town": String(context.get("town", "")), "seed": seed_value,
			"front": {}, "stories": [], "filler": {}}
	var chosen: Array = _choose(ranked)
	for index: int in chosen.size():
		var candidate: Dictionary = chosen[index]
		var entry: Dictionary = _entry(candidate, table, context, used_players, previous)
		if index == 0:
			paper["front"] = entry
		else:
			(paper["stories"] as Array).append(entry)
	paper["filler"] = _filler(table, context, used_players, previous)
	return paper


## The candidates, most newsworthy first (ties broken by the seed), one per topic.
static func _ranked(by_kind: Dictionary, table: Dictionary, seed_value: int) -> Array:
	var candidates: Array = []
	for kind: String in by_kind:
		var list: Array = by_kind[kind]
		var story: Dictionary = table[kind]
		candidates.append({
			"kind": kind,
			"score": float(story.get("weight", 1)) + minf(float(list.size() - 1), 2.0) * 0.5,
			"fact": list[0],
			"count": list.size(),
			"topic": String(story.get("topic", kind)),
			"section": String(story.get("section", "society")),
			"tie": hash([seed_value, kind]),
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["score"]), float(b["score"])):
			return float(a["score"]) > float(b["score"])
		return int(a["tie"]) < int(b["tie"]))
	var topics: Dictionary = {}
	var ranked: Array = []
	for candidate: Dictionary in candidates:
		if topics.has(candidate["topic"]):
			continue
		topics[candidate["topic"]] = true
		ranked.append(candidate)
	return ranked


## The front page (the first) and the secondary stories: sections not yet
## used first, then whatever news is left up to MIN_SECONDARY.
static func _choose(ranked: Array) -> Array:
	if ranked.is_empty():
		return []
	var chosen: Array = [ranked[0]]
	var sections: Dictionary = {String(ranked[0]["section"]): true}
	var left: Array = ranked.slice(1)
	for candidate: Dictionary in left.duplicate():
		if chosen.size() > MAX_SECONDARY:
			break
		if not sections.has(candidate["section"]):
			sections[candidate["section"]] = true
			chosen.append(candidate)
			left.erase(candidate)
	for candidate: Dictionary in left:
		if chosen.size() > MIN_SECONDARY:
			break
		chosen.append(candidate)
	return chosen


static func _entry(candidate: Dictionary, table: Dictionary, context: Dictionary, used_players: Array,
		previous: Dictionary) -> Dictionary:
	var kind: String = String(candidate["kind"])
	var fact: Dictionary = candidate["fact"]
	var seed_value: int = int(context.get("seed", 0))
	return {
		"id": kind,
		"variant": pick_variant(table[kind], fact.get("tags", []), seed_value, kind, int(previous.get(kind, -1))),
		"slots": _slots(kind, fact, int(candidate["count"]), context, used_players),
	}


## Which variant of a story to print: the ones for this kind of box (often),
## else the generic ones; never the one the last paper used, if there is another.
static func pick_variant(story: Dictionary, tags: Array, seed_value: int, kind: String, last: int) -> int:
	var variants: Array = story.get("variants", [])
	var tagged: Array[int] = []
	var generic: Array[int] = []
	for index: int in variants.size():
		var variant_tags: Array = (variants[index] as Dictionary).get("tags", [])
		if variant_tags.is_empty():
			generic.append(index)
		elif variant_tags.any(func(tag: Variant) -> bool: return tags.has(tag)):
			tagged.append(index)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, kind, "variant"])
	var pool: Array[int] = tagged if not tagged.is_empty() and rng.randf() < TAGGED_CHANCE else generic
	if pool.is_empty():
		pool = tagged
	if pool.size() > 1 and pool.has(last):
		pool = pool.duplicate()
		pool.erase(last)
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else 0


static func _slots(kind: String, fact: Dictionary, count: int, context: Dictionary, used_players: Array) -> Dictionary:
	var seed_value: int = int(context.get("seed", 0))
	var neighbors: Array = catalog().get("neighbors", [])
	var house: int = int(fact.get("house", -1))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, kind, "slots"])
	return {
		"town": String(context.get("town", "")),
		"house": house + 1 if house >= 0 else rng.randi_range(1, 3),
		"neighbor": String(neighbors[rng.randi() % neighbors.size()]) if not neighbors.is_empty() else "",
		"player": _player(context.get("crew", []), int(fact.get("peer", 0)), seed_value, kind, used_players),
		"km": snappedf(float(context.get("km", 0.0)), 0.1),
		"minutes": int(context.get("minutes", 0)),
		"count": count,
	}


## Who the story is about: the player behind the fact if it has one, else a
## seeded member of the crew that hasn't had a story yet (so a paper doesn't
## blame the same person four times). Their nickname as it travels
## (Nickname.resolve: typed text, or a funny one as a LocText line).
static func _player(crew: Array, peer: int, seed_value: int, kind: String, used_players: Array) -> Variant:
	var members: Array = crew.filter(func(member: Variant) -> bool: return member is Dictionary)
	if members.is_empty():
		return NICKNAME.resolve("", hash([seed_value, 0]))
	var pick: Dictionary = {}
	for member: Dictionary in members:
		if peer != 0 and int(member.get("peer", 0)) == peer:
			pick = member
	if pick.is_empty():
		var free: Array = members.filter(func(member: Dictionary) -> bool:
			return not used_players.has(int(member.get("peer", 0))))
		var pool: Array = free if not free.is_empty() else members
		pick = pool[posmod(hash([seed_value, kind, "player"]), pool.size())]
	used_players.append(int(pick.get("peer", 0)))
	return NICKNAME.resolve(String(pick.get("nick", "")), hash([seed_value, int(pick.get("peer", 0))]))


## The one piece that is not news (a classified, a horoscope, a forecast): by
## the seed, and not the kind the last paper ran.
static func _filler(table: Dictionary, context: Dictionary, used_players: Array, previous: Dictionary) -> Dictionary:
	var kinds: Array = []
	for kind: String in table:
		if bool(table[kind].get("filler", false)):
			kinds.append(kind)
	kinds.sort()
	if kinds.is_empty():
		return {}
	var seed_value: int = int(context.get("seed", 0))
	var fresh: Array = kinds.filter(func(kind: String) -> bool: return not previous.has(kind))
	var pool: Array = fresh if not fresh.is_empty() else kinds
	var kind: String = pool[posmod(hash([seed_value, "filler"]), pool.size())]
	var fact: Dictionary = {"kind": kind, "house": -1, "tags": [], "peer": 0}
	return {
		"id": kind,
		"variant": pick_variant(table[kind], [], seed_value, kind, int(previous.get(kind, -1))),
		"slots": _slots(kind, fact, 1, context, used_players),
	}


## Every entry of a paper, front page first.
static func entries(paper: Dictionary) -> Array:
	var all: Array = []
	if not (paper.get("front", {}) as Dictionary).is_empty():
		all.append(paper["front"])
	all.append_array(paper.get("stories", []))
	if not (paper.get("filler", {}) as Dictionary).is_empty():
		all.append(paper["filler"])
	return all


## What a peer remembers of this paper to avoid repeating it next time:
## kind -> variant.
static func variants_used(paper: Dictionary) -> Dictionary:
	var used: Dictionary = {}
	for entry: Dictionary in entries(paper):
		used[String(entry["id"])] = int(entry["variant"])
	return used


## Whether a paper that arrived over the network can be read: a known id and
## a variant that exists for every entry. A newer or older host's paper that
## doesn't pass is skipped rather than crashing the results screen.
static func is_valid(paper: Variant) -> bool:
	if paper is not Dictionary or (paper as Dictionary).get("front", {}) is not Dictionary:
		return false
	if ((paper as Dictionary).get("front", {}) as Dictionary).is_empty():
		return false
	var table: Dictionary = stories()
	for entry: Variant in entries(paper):
		if entry is not Dictionary or not table.has(String(entry.get("id", ""))):
			return false
		var variants: Array = table[String(entry["id"])].get("variants", [])
		var index: int = int(entry.get("variant", -1))
		if index < 0 or index >= variants.size() or entry.get("slots", {}) is not Dictionary:
			return false
	return true


## One entry as this peer reads it: {id, headline, body, section, section_text}.
static func read(entry: Dictionary) -> Dictionary:
	var story: Dictionary = stories().get(String(entry.get("id", "")), {})
	if story.is_empty():
		return {}
	var variants: Array = story.get("variants", [])
	var variant: Dictionary = variants[clampi(int(entry.get("variant", 0)), 0, variants.size() - 1)]
	var slots: Dictionary = entry.get("slots", {})
	var section: String = String(story.get("section", "society"))
	return {
		"id": String(entry["id"]),
		"headline": fill(TranslationServer.translate(StringName(variant["h"])), slots),
		"body": fill(TranslationServer.translate(StringName(variant["b"])), slots),
		"section": section,
		"section_text": TranslationServer.translate(StringName(catalog().get("sections", {}).get(section, ""))),
	}


## A text with its {slots} filled in.
static func fill(text: String, slots: Dictionary) -> String:
	for slot: String in SLOT_NAMES:
		if slots.has(slot):
			text = text.replace("{%s}" % slot, slot_text(slots[slot]))
	return text


static func slot_text(value: Variant) -> String:
	var text: String
	if value is Array:
		text = LOC_TEXT.render(value)
	elif value is float:
		text = String.num(value, 1)
	else:
		text = str(value)
	return text.substr(0, MAX_SLOT_TEXT)
