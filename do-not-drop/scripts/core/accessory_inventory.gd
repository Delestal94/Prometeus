class_name AccessoryInventory
extends RefCounted
## Who owns which accessory and what each one wears (N-923). Pure state, no
## scene and no network: CrewProgression holds one (host-owned, saved with the
## campaign) and every rule of the shop is enforced here, so the network layer
## only has to ask.
##
## Owners are opaque strings: the game uses the player colour key ("mint",
## "coral"...), not the peer id, so an inventory survives a change of peer id.
## Each accessory exists once (decided 2026-10-02): granting one somebody has
## fails, and give()/remove() move or take it, never copy it. Wearing is one
## accessory per slot, and only of what the owner owns.

## Emitted after any change to `owner`'s accessories (owned or worn).
signal changed(owner: String)

var _owned: Dictionary = {} # owner -> Array[StringName], in the order they were granted
var _equipped: Dictionary = {} # owner -> {slot: id}


## Gives `id` to `owner`. False (and nothing changes) for an unknown id, an
## empty owner, or an accessory that somebody already has, the owner included.
func grant(owner: String, id: StringName) -> bool:
	if owner.is_empty() or not AccessoryCatalog.has(id) or owner_of(id) != "":
		return false
	_add(owner, id)
	changed.emit(owner)
	return true


## Takes `id` away from `owner` (taking it off first). False if they don't have it.
func remove(owner: String, id: StringName) -> bool:
	if not owns(owner, id):
		return false
	_take(owner, id)
	changed.emit(owner)
	return true


## Moves `id` from `from_owner` to `to_owner`: dropping it and having someone
## pick it up, or giving it. It is taken off first, and it stays a single copy.
func give(from_owner: String, to_owner: String, id: StringName) -> bool:
	if to_owner.is_empty() or from_owner == to_owner or not owns(from_owner, id):
		return false
	_take(from_owner, id)
	_add(to_owner, id)
	changed.emit(from_owner)
	changed.emit(to_owner)
	return true


func owns(owner: String, id: StringName) -> bool:
	return _owned.has(owner) and (_owned[owner] as Array[StringName]).has(id)


## Who has `id`, or "" if nobody (not bought yet, or on the ground).
func owner_of(id: StringName) -> String:
	for owner: String in _owned:
		if (_owned[owner] as Array[StringName]).has(id):
			return owner
	return ""


## What `owner` has, in the order they got it (a copy).
func owned_by(owner: String) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_owned.get(owner, []))
	return result


## Puts on `id`. It replaces whatever is worn in the same slot. False if the
## owner doesn't have it (nobody wears what they don't own).
func equip(owner: String, id: StringName) -> bool:
	if not owns(owner, id):
		return false
	var slot: StringName = AccessoryCatalog.slot_of(id)
	var slots: Dictionary = _equipped.get(owner, {})
	if slots.get(slot, &"") == id:
		return true
	slots[slot] = id
	_equipped[owner] = slots
	changed.emit(owner)
	return true


## Takes off whatever is worn in `slot`. False if the slot was empty.
func unequip(owner: String, slot: StringName) -> bool:
	var slots: Dictionary = _equipped.get(owner, {})
	if not slots.has(slot):
		return false
	slots.erase(slot)
	if slots.is_empty():
		_equipped.erase(owner)
	changed.emit(owner)
	return true


## The accessory worn in `slot`, or &"" .
func equipped_in(owner: String, slot: StringName) -> StringName:
	return StringName(Dictionary(_equipped.get(owner, {})).get(slot, &""))


## {slot: id} of everything worn (a copy): what the other players need to draw.
func equipped_by(owner: String) -> Dictionary:
	return Dictionary(_equipped.get(owner, {})).duplicate()


func is_equipped(owner: String, id: StringName) -> bool:
	return owns(owner, id) and equipped_in(owner, AccessoryCatalog.slot_of(id)) == id


func is_empty() -> bool:
	return _owned.is_empty()


func clear() -> void:
	var owners: Array = _owned.keys()
	_owned.clear()
	_equipped.clear()
	for owner: String in owners:
		changed.emit(owner)


## One owner's entry, {"owned": [id...], "equipped": {slot: id}} (plain strings,
## ready for JSON); {} if they have nothing.
func entry_of(owner: String) -> Dictionary:
	if not _owned.has(owner):
		return {}
	var owned: Array[String] = []
	for id: StringName in _owned[owner]:
		owned.append(String(id))
	var worn: Dictionary = {}
	for slot: StringName in Dictionary(_equipped.get(owner, {})):
		worn[String(slot)] = String(_equipped[owner][slot])
	return {"owned": owned, "equipped": worn}


## Takes `owner`'s whole entry out and returns it (entry_of format), so it can
## be kept for them while somebody else uses the colour.
func take_entry(owner: String) -> Dictionary:
	var entry: Dictionary = entry_of(owner)
	if entry.is_empty():
		return entry
	_owned.erase(owner)
	_equipped.erase(owner)
	changed.emit(owner)
	return entry


## Adds what an entry (entry_of format, maybe from a file) lists to `owner`,
## keeping what they already have. Anything that can't hold is skipped without
## failing: unknown ids, an id somebody else has, wrong types, a worn item that
## isn't owned or is in the wrong slot. Returns how many accessories were added.
func merge_entry(owner: String, raw: Variant) -> int:
	if owner.is_empty() or not raw is Dictionary:
		return 0
	var added: int = 0
	var raw_owned: Variant = Dictionary(raw).get("owned", [])
	for raw_id: Variant in raw_owned if raw_owned is Array else []:
		if (raw_id is String or raw_id is StringName) and grant(owner, StringName(raw_id)):
			added += 1
	var raw_worn: Variant = Dictionary(raw).get("equipped", {})
	for raw_slot: Variant in raw_worn if raw_worn is Dictionary else {}:
		var raw_id: Variant = Dictionary(raw_worn)[raw_slot]
		if not (raw_id is String or raw_id is StringName) or not (raw_slot is String or raw_slot is StringName):
			continue
		var id := StringName(raw_id)
		var slot := StringName(raw_slot)
		if AccessoryCatalog.slot_of(id) == slot and equipped_in(owner, slot) == &"":
			equip(owner, id)
	return added


## {owner: entry} of everyone with something, for the campaign file.
func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for owner: String in _owned:
		result[owner] = entry_of(owner)
	return result


## Replaces everything with what `raw` (to_dict format, maybe from a file) says.
## `allowed_owners` limits who may appear (empty = anyone). Malformed or unknown
## parts are dropped, never fatal; one copy per id holds even for a doctored file.
func load_dict(raw: Variant, allowed_owners: Array = []) -> void:
	var touched: Array = _owned.keys()
	_owned.clear()
	_equipped.clear()
	if raw is Dictionary:
		for raw_owner: Variant in raw:
			if not raw_owner is String:
				continue
			var owner: String = raw_owner
			if not allowed_owners.is_empty() and not allowed_owners.has(owner):
				continue
			merge_entry(owner, raw[raw_owner])
	for owner: Variant in _owned:
		if not touched.has(owner):
			touched.append(owner)
	for owner: Variant in touched:
		changed.emit(String(owner))


func _add(owner: String, id: StringName) -> void:
	if not _owned.has(owner):
		_owned[owner] = [] as Array[StringName]
	(_owned[owner] as Array[StringName]).append(id)


func _take(owner: String, id: StringName) -> void:
	(_owned[owner] as Array[StringName]).erase(id)
	if (_owned[owner] as Array[StringName]).is_empty():
		_owned.erase(owner)
	var slot: StringName = AccessoryCatalog.slot_of(id)
	var slots: Dictionary = _equipped.get(owner, {})
	if slots.get(slot, &"") == id:
		slots.erase(slot)
		if slots.is_empty():
			_equipped.erase(owner)
