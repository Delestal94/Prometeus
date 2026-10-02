class_name AccessoryGround
extends RefCounted
## The accessories lying on the ground (N-923.5), pure: no scene, no network.
## The host keeps one in AccessoryNet and every client a copy of it, so a
## pickup has the same id, accessory, owner and place on every peer.
##
## A dropped accessory is still its owner's (AccessoryInventory keeps it in
## their list) until someone else picks it up: that is what makes "never lost"
## and "one copy" hold -- the shop sees it as taken, a save keeps it with its
## owner, and giving it back is just taking the pickup away. This only says
## which ones are out and where.
##
## A pickup: {id (int > 0, never reused in this process), accessory (StringName),
## owner (colour key), dropper (peer id), position (Vector3), at_msec (host
## clock, when it was dropped; 0 on a client)}.

## A pickup is on the ground now (on a client: the host said so).
signal pickup_added(pickup_id: int, pickup: Dictionary)
## A pickup is gone: picked up, given back, or the host stopped listing it.
signal pickup_removed(pickup_id: int)

var _pickups: Dictionary = {} # id -> pickup
var _next_id: int = 1


## Puts `accessory` (owner's, dropped by peer `dropper`) on the ground at
## `position`. Returns the new pickup id, or 0 if it can't be there: an unknown
## accessory, no owner, a position that isn't finite, or one already lying.
func add(accessory: StringName, owner: String, dropper: int, position: Vector3, at_msec: int) -> int:
	if not AccessoryCatalog.has(accessory) or owner.is_empty() or not position.is_finite() \
			or pickup_of(accessory) != 0:
		return 0
	var pickup_id: int = _next_id
	_next_id += 1
	_pickups[pickup_id] = {"id": pickup_id, "accessory": accessory, "owner": owner, "dropper": dropper,
		"position": position, "at_msec": at_msec}
	pickup_added.emit(pickup_id, get_pickup(pickup_id))
	return pickup_id


## Takes pickup `pickup_id` off the ground and returns it ({} if there was none).
func remove(pickup_id: int) -> Dictionary:
	if not _pickups.has(pickup_id):
		return {}
	var pickup: Dictionary = _pickups[pickup_id]
	_pickups.erase(pickup_id)
	pickup_removed.emit(pickup_id)
	return pickup


func has(pickup_id: int) -> bool:
	return _pickups.has(pickup_id)


## A copy of pickup `pickup_id`, {} if it isn't on the ground.
func get_pickup(pickup_id: int) -> Dictionary:
	return Dictionary(_pickups.get(pickup_id, {})).duplicate()


## The pickup holding `accessory`, 0 if it isn't on the ground.
func pickup_of(accessory: StringName) -> int:
	for pickup_id: int in _pickups:
		if StringName((_pickups[pickup_id] as Dictionary)["accessory"]) == accessory:
			return pickup_id
	return 0


## Every pickup id on the ground, oldest first.
func ids() -> Array[int]:
	var result: Array[int] = []
	result.assign(_pickups.keys())
	return result


## The pickups whose accessory belongs to `owner`.
func owned_by(owner: String) -> Array[int]:
	var result: Array[int] = []
	for pickup_id: int in _pickups:
		if String((_pickups[pickup_id] as Dictionary)["owner"]) == owner:
			result.append(pickup_id)
	return result


## The pickups that have lain `lifetime_msec` or more at `now_msec` (host clock).
func expired(now_msec: int, lifetime_msec: int) -> Array[int]:
	var result: Array[int] = []
	for pickup_id: int in _pickups:
		if now_msec - int((_pickups[pickup_id] as Dictionary)["at_msec"]) >= lifetime_msec:
			result.append(pickup_id)
	return result


## Takes away every pickup whose owner no longer has its accessory in
## `inventory` (the campaign was reset, or the colour's entry was set aside):
## a pickup only stands for something its owner still owns. Returns them.
func prune(inventory: AccessoryInventory) -> Array[int]:
	var stale: Array[int] = []
	for pickup_id: int in _pickups:
		var pickup: Dictionary = _pickups[pickup_id]
		if not inventory.owns(String(pickup["owner"]), StringName(pickup["accessory"])):
			stale.append(pickup_id)
	for pickup_id: int in stale:
		remove(pickup_id)
	return stale


func is_empty() -> bool:
	return _pickups.is_empty()


func clear() -> void:
	for pickup_id: int in ids():
		remove(pickup_id)


## The pickups as plain values for the wire: [{id, accessory (String), owner,
## dropper, position}] (the host's clock stays on the host).
func to_array() -> Array:
	var result: Array = []
	for pickup_id: int in _pickups:
		var pickup: Dictionary = _pickups[pickup_id]
		result.append({"id": pickup_id, "accessory": String(pickup["accessory"]), "owner": pickup["owner"],
			"dropper": pickup["dropper"], "position": pickup["position"]})
	return result


## Replaces the pickups with what `raw` (to_array() format, from the host) lists,
## emitting pickup_removed for those gone and pickup_added for those new (one
## that moved or changed hands counts as both). Anything malformed is skipped:
## unknown accessories, owners outside `allowed_owners` (empty = anyone), a
## non-positive id, a position that isn't finite, a second pickup of the same
## accessory (so never more than the catalogue holds).
func load_array(raw: Variant, allowed_owners: Array = []) -> void:
	var incoming: Dictionary = {}
	var seen: Dictionary = {}
	for item: Variant in raw if raw is Array else []:
		if incoming.size() >= AccessoryCatalog.ACCESSORIES.size():
			break
		var pickup: Dictionary = _parsed(item, allowed_owners)
		if pickup.is_empty() or incoming.has(pickup["id"]) or seen.has(pickup["accessory"]):
			continue
		incoming[pickup["id"]] = pickup
		seen[pickup["accessory"]] = true
	for pickup_id: int in ids():
		if not incoming.has(pickup_id) or not _same(_pickups[pickup_id], incoming[pickup_id]):
			remove(pickup_id)
	for pickup_id: int in incoming:
		if _pickups.has(pickup_id):
			continue
		_pickups[pickup_id] = incoming[pickup_id]
		_next_id = maxi(_next_id, pickup_id + 1)
		pickup_added.emit(pickup_id, get_pickup(pickup_id))


func _parsed(item: Variant, allowed_owners: Array) -> Dictionary:
	if not item is Dictionary:
		return {}
	var entry: Dictionary = item
	var raw_id: Variant = entry.get("id", 0)
	var raw_accessory: Variant = entry.get("accessory", "")
	var raw_owner: Variant = entry.get("owner", "")
	var raw_position: Variant = entry.get("position", null)
	var raw_dropper: Variant = entry.get("dropper", 0)
	if not raw_id is int or int(raw_id) <= 0 or not (raw_accessory is String or raw_accessory is StringName) \
			or not raw_owner is String or not raw_position is Vector3 or not raw_dropper is int:
		return {}
	var accessory := StringName(raw_accessory)
	var owner: String = raw_owner
	var position: Vector3 = raw_position
	if not AccessoryCatalog.has(accessory) or owner.is_empty() or not position.is_finite() \
			or (not allowed_owners.is_empty() and not allowed_owners.has(owner)):
		return {}
	return {"id": int(raw_id), "accessory": accessory, "owner": owner, "dropper": int(raw_dropper),
		"position": position, "at_msec": 0}


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a["accessory"] == b["accessory"] and a["owner"] == b["owner"] and a["position"] == b["position"]
