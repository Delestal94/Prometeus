class_name PackedBox
extends RefCounted
## A box being packed in the warehouse (expansion D-0212): its size, what sits
## in each cell of its packing grid, padding, tape, label and stamps.
##
## Pure data, like Pallet and Inventory: no node, no autoload. The grid is
## CompanyTuning.BOX_CELLS[box_size] cells of CompanyTuning.GRID_CELL_M; each
## occupied cell holds a product id or FILL. Products keep their
## ProductDefinition.cells as placed (no rotation in F1). D-0213 turns a packed
## box into a DeliveryPackage; the packing station (D-0701...) builds it.

const FILL: StringName = &"fill"

var box_size: StringName = &""
## Vector3i cell -> product id or FILL.
var grid: Dictionary = {}
var taped: bool = false
var label_order_id: StringName = &""
var stamps: Array[StringName] = []
## Placed products, in order: {"product": StringName, "origin": Vector3i, "cells": Vector3i}.
var items: Array[Dictionary] = []


func _init(size: StringName = &"M") -> void:
	box_size = size


## Cells of the box (X x Y x Z); zero for an unknown size.
func dimensions() -> Vector3i:
	return CompanyTuning.BOX_CELLS.get(box_size, Vector3i.ZERO)


func total_cells() -> int:
	var d: Vector3i = dimensions()
	return d.x * d.y * d.z


## Places a product with its lowest corner at origin. False, changing nothing,
## if it sticks out of the box or overlaps a product or padding.
func place(product: ProductDefinition, origin: Vector3i) -> bool:
	if product == null:
		return false
	return _place_cells(product.id, product.cells, origin)


## Pads the first n empty cells (x, then y, then z order). Returns how many it filled.
func fill_free_cells(n: int) -> int:
	var filled: int = 0
	for cell: Vector3i in _all_cells():
		if filled >= n:
			break
		if not grid.has(cell):
			grid[cell] = FILL
			filled += 1
	return filled


## Product id -> units in the box.
func contents() -> Dictionary:
	var out: Dictionary = {}
	for item: Dictionary in items:
		var id: StringName = item["product"]
		out[id] = int(out.get(id, 0)) + 1
	return out


## Share of the box's cells that hold nothing (0..1).
func free_ratio() -> float:
	var total: int = total_cells()
	if total == 0:
		return 0.0
	return float(total - grid.size()) / total


## Share of the cells not taken by products that hold padding (0..1). 1.0 when
## every gap is padded; 0.0 with no padding, or when products fill the box.
func fill_ratio() -> float:
	var product_cells: int = 0
	var fill_cells: int = 0
	for value: StringName in grid.values():
		if value == FILL:
			fill_cells += 1
		else:
			product_cells += 1
	var gaps: int = total_cells() - product_cells
	if gaps <= 0:
		return 0.0
	return float(fill_cells) / gaps


## JSON-friendly copy (Vector3i as [x, y, z]): travels by network and lives in a save.
func to_dict() -> Dictionary:
	var placed: Array = []
	for item: Dictionary in items:
		placed.append(
			{
				"product": String(item["product"]),
				"origin": _vec_to_array(item["origin"]),
				"cells": _vec_to_array(item["cells"]),
			}
		)
	var fill: Array = []
	for cell: Vector3i in _all_cells():
		if grid.get(cell) == FILL:
			fill.append(_vec_to_array(cell))
	var stamp_list: Array = []
	for stamp: StringName in stamps:
		stamp_list.append(String(stamp))
	return {
		"box_size": String(box_size),
		"items": placed,
		"fill": fill,
		"taped": taped,
		"label_order_id": String(label_order_id),
		"stamps": stamp_list,
	}


## Rebuilds a box from to_dict() (also after a JSON round trip). Items or
## padding that no longer fit are dropped, never overlapped.
static func from_dict(d: Dictionary) -> PackedBox:
	var box := PackedBox.new(StringName(str(d.get("box_size", ""))))
	for raw: Variant in d.get("items", []):
		if raw is Dictionary:
			var item: Dictionary = raw
			box._place_cells(
				StringName(str(item.get("product", ""))),
				_array_to_vec(item.get("cells", [])),
				_array_to_vec(item.get("origin", []))
			)
	for raw: Variant in d.get("fill", []):
		var cell: Vector3i = _array_to_vec(raw)
		if box._inside(cell) and not box.grid.has(cell):
			box.grid[cell] = FILL
	box.taped = bool(d.get("taped", false))
	box.label_order_id = StringName(str(d.get("label_order_id", "")))
	for stamp: Variant in d.get("stamps", []):
		box.stamps.append(StringName(str(stamp)))
	return box


func _place_cells(id: StringName, size: Vector3i, origin: Vector3i) -> bool:
	if id == &"" or id == FILL or size.x < 1 or size.y < 1 or size.z < 1:
		return false
	var cells: Array[Vector3i] = []
	for x: int in size.x:
		for y: int in size.y:
			for z: int in size.z:
				var cell: Vector3i = origin + Vector3i(x, y, z)
				if not _inside(cell) or grid.has(cell):
					return false
				cells.append(cell)
	for cell: Vector3i in cells:
		grid[cell] = id
	items.append({"product": id, "origin": origin, "cells": size})
	return true


func _inside(cell: Vector3i) -> bool:
	var d: Vector3i = dimensions()
	return (
		cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < d.x and cell.y < d.y and cell.z < d.z
	)


func _all_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var d: Vector3i = dimensions()
	for z: int in d.z:
		for y: int in d.y:
			for x: int in d.x:
				out.append(Vector3i(x, y, z))
	return out


static func _vec_to_array(v: Vector3i) -> Array:
	return [v.x, v.y, v.z]


static func _array_to_vec(raw: Variant) -> Vector3i:
	if raw is Array and raw.size() == 3:
		return Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
	return Vector3i(-1, -1, -1)
