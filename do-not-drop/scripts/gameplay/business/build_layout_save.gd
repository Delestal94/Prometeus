class_name BuildLayoutSave
extends RefCounted
## Cleans the shed layout read from a company save (expansion D-0909, "Modo Empresa").
##
## The layout is saved as `CompanyState.layout` (`{id, x, z, turns}` per piece). After a JSON round
## trip the numbers come back as floats and a hand-edited or older file may hold pieces that no
## longer fit. `sanitize()` rebuilds the list with integer fields and keeps only the pieces that
## BuildPlacement would accept one after the other on the saved stage's grid (known definition, in
## bounds, off the dock and exit, not overlapping, walking paths open). The rest are dropped, never
## fixed up, so a loaded layout is always one the build mode could have produced.
## Nothing here names autoloads or UI classes (N-919).


## Pieces of `raw` that fit the grid of `stage`, in their original order. Anything that is not a
## piece dictionary with a numeric position is skipped.
static func sanitize(raw: Variant, stage: int) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	_replay(raw, stage, kept)
	return kept


## Why sanitize() would not keep `raw` whole on the grid of `stage`: BuildPlacement's reason for the first
## piece it drops (fixed_area, blocks_path, out_of_bounds...; no_definition for an entry that is not a
## piece), or &"" when it keeps every one. Growing the shed asks it first (D-0910.2): the dock and the exit
## move with the walls, and a layout the bigger stage would not keep whole would load differently later.
static func misfit(raw: Variant, stage: int) -> StringName:
	var kept: Array[Dictionary] = []
	return _replay(raw, stage, kept)


## sanitize()'s pass: the pieces of `raw` that fit, appended to `kept` in order; returns the reason the
## first one left out was refused (&"" when none was; nothing to keep when `raw` is not an Array).
static func _replay(raw: Variant, stage: int, kept: Array[Dictionary]) -> StringName:
	var first: StringName = &""
	if not raw is Array:
		return first
	var placement := BuildPlacement.new()
	WarehouseStages.apply_to(stage, placement)
	for item: Variant in raw:
		var piece: Dictionary = _normalized(item)
		var reason: StringName = BuildPlacement.REASON_NO_DEFINITION
		if not piece.is_empty():
			var def: PlaceableDefinition = PlaceableShop.definition(StringName(piece["id"]))
			var result: Dictionary = placement.preview(kept, def, piece["x"], piece["z"], piece["turns"])
			reason = result["reason"]
			if bool(result["ok"]):
				kept.append(piece)
		if reason != BuildPlacement.REASON_OK and first == &"":
			first = reason
	return first


## `{id: String, x: int, z: int, turns: 0-3[, uid: String]}` from a saved entry, or {} when it is not one.
static func _normalized(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var entry: Dictionary = item
	var id: Variant = entry.get("id")
	if not (id is String or id is StringName) or str(id) == "":
		return {}
	var x: Variant = entry.get("x")
	var z: Variant = entry.get("z")
	if not (_is_num(x) and _is_num(z)):
		return {}
	var turns: Variant = entry.get("turns", 0)
	var piece: Dictionary = {
		"id": str(id),
		"x": int(x),
		"z": int(z),
		"turns": posmod(int(turns) if _is_num(turns) else 0, 4),
	}
	var uid: String = str(entry.get("uid", ""))
	if uid != "":
		piece["uid"] = uid  # the piece's name in the shed (D-0911): its stock is stored under it
	return piece


static func _is_num(raw: Variant) -> bool:
	return raw is int or raw is float
