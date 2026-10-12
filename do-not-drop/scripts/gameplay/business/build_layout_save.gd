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
	if not raw is Array:
		return kept
	var placement := BuildPlacement.new()
	WarehouseStages.apply_to(stage, placement)
	for item: Variant in raw:
		var piece: Dictionary = _normalized(item)
		if piece.is_empty():
			continue
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(piece["id"]))
		var result: Dictionary = placement.preview(kept, def, piece["x"], piece["z"], piece["turns"])
		if bool(result["ok"]):
			kept.append(piece)
	return kept


## `{id: String, x: int, z: int, turns: 0-3}` from a saved entry, or {} when it is not one.
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
	return {
		"id": str(id),
		"x": int(x),
		"z": int(z),
		"turns": posmod(int(turns) if _is_num(turns) else 0, 4),
	}


static func _is_num(raw: Variant) -> bool:
	return raw is int or raw is float
