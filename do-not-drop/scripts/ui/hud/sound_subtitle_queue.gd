class_name SoundSubtitleQueue
extends RefCounted
## The sound subtitles (N-965) that come and go with the world's sounds, as
## opposed to the at-risk trap's standing one (HudPrompts.refresh_sound_subtitle):
## several at once, each with a priority and a lifetime, the loudest-meaning
## first and at most MAX_VISIBLE on screen. Pure data, no nodes: HudPrompts
## decides what to push from the EventBus and draws what lines() returns.
##
## An entry has a key: pushing the same key again (a second honk, a bell that
## rings twice) replaces the text and restarts its timer instead of stacking.
## Priorities (docs/tareas/N-965.md, inventory): 70 animal going for a box,
## 50 horn, 45 doorbell, 40 customer's reaction, 20 weather.

const MAX_VISIBLE: int = 3

## [{key, text, priority, left, serial}]
var _entries: Array[Dictionary] = []
var _serial: int = 0
var _shown: String = ""


## Adds (or refreshes, by key) a subtitle that lasts `seconds`.
func push(key: StringName, text: String, priority: int, seconds: float) -> void:
	if text.is_empty() or seconds <= 0.0:
		return
	_serial += 1
	for entry: Dictionary in _entries:
		if entry["key"] == key:
			entry["text"] = text
			entry["priority"] = priority
			entry["left"] = seconds
			entry["serial"] = _serial
			return
	_entries.append({"key": key, "text": text, "priority": priority, "left": seconds, "serial": _serial})


## Ages every entry; true when the visible lines changed (something expired, or
## a pushed entry now shows), so the caller redraws only then.
func tick(delta: float) -> bool:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		entry["left"] = float(entry["left"]) - delta
		if float(entry["left"]) > 0.0:
			kept.append(entry)
	_entries = kept
	return sync_shown()


## The visible lines, highest priority first, newest first among equals.
func lines() -> PackedStringArray:
	var ordered: Array[Dictionary] = _entries.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] != b["priority"]:
			return int(a["priority"]) > int(b["priority"])
		return int(a["serial"]) > int(b["serial"]))
	var out := PackedStringArray()
	for entry: Dictionary in ordered:
		if out.size() >= MAX_VISIBLE:
			break
		out.append(String(entry["text"]))
	return out


## True when lines() differs from what the caller last drew.
func sync_shown() -> bool:
	var now: String = "\n".join(lines())
	if now == _shown:
		return false
	_shown = now
	return true


func is_empty() -> bool:
	return _entries.is_empty()


func size() -> int:
	return _entries.size()


## Drops everything (the option was turned off). True if something was showing.
func clear() -> bool:
	_entries.clear()
	return sync_shown()


## Which way a point is from the camera, as an arrow, from the point in the
## camera's own space (-Z ahead, +X right): the horizontal bearing in four
## quarters, so ahead is "↑" and behind "↓" (the same glyphs the callouts
## use, ping arrows in hud_notices.gd). "" when it is basically on top of the
## listener (inside the truck there is no "where from").
static func arrow(local: Vector3, near_radius: float = 3.0) -> String:
	if Vector2(local.x, local.z).length() < near_radius:
		return ""
	if absf(local.x) > absf(local.z):
		return "→" if local.x > 0.0 else "←"
	return "↓" if local.z > 0.0 else "↑"
