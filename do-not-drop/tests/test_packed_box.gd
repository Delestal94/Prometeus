extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_packed_box.gd
##
## Packed box (expansion D-0212, packed_box.gd):
## - in an M box (3x3x3) a 1x1x2 product fits at 0,0,0 but not at 0,0,2 (sticks
##   out), and never over another product;
## - fill_free_cells() pads only empty cells, never a product, and stops when full;
## - contents(), free_ratio() and fill_ratio() count units, empty cells and padded gaps;
## - to_dict() survives a JSON round trip and from_dict() rebuilds an equal box.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_place()
	_test_fill()
	_test_ratios()
	_test_round_trip()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _product(id: StringName, cells: Vector3i) -> ProductDefinition:
	var p := ProductDefinition.new()
	p.id = id
	p.cells = cells
	return p


func _test_place() -> void:
	var box := PackedBox.new(&"M")
	var tall: ProductDefinition = _product(&"sourdough", Vector3i(1, 1, 2))
	_expect(box.dimensions() == Vector3i(3, 3, 3), "an M box is 3x3x3")
	_expect(box.place(tall, Vector3i(0, 0, 0)), "1x1x2 fits at 0,0,0")
	_expect(not box.place(tall, Vector3i(0, 0, 2)), "1x1x2 does not fit at 0,0,2")
	_expect(not box.place(tall, Vector3i(0, 0, 1)), "it does not overlap the first one")
	_expect(not box.place(tall, Vector3i(-1, 0, 0)), "negative origin is refused")
	_expect(box.items.size() == 1 and box.grid.size() == 2, "failed places change nothing")
	_expect(box.place(tall, Vector3i(1, 0, 0)), "it fits next to the first one")
	_expect(not PackedBox.new(&"XXL").place(tall, Vector3i.ZERO), "unknown size takes nothing")


func _test_fill() -> void:
	var box := PackedBox.new(&"S")
	box.place(_product(&"hen", Vector3i(2, 1, 1)), Vector3i.ZERO)
	_expect(box.fill_free_cells(3) == 3, "3 cells padded")
	_expect(box.grid[Vector3i(0, 0, 0)] == &"hen", "padding does not cover the product")
	_expect(box.fill_free_cells(10) == 3, "only the 3 empty cells left get padded")
	_expect(box.fill_free_cells(1) == 0, "a full box takes no more padding")
	_expect(box.contents() == {&"hen": 1}, "padding is not content")


func _test_ratios() -> void:
	var box := PackedBox.new(&"S")
	_expect(is_equal_approx(box.free_ratio(), 1.0), "an empty box is all free")
	_expect(is_equal_approx(box.fill_ratio(), 0.0), "an empty box has no padding")
	var cube: ProductDefinition = _product(&"puppy", Vector3i(1, 1, 1))
	box.place(cube, Vector3i(0, 0, 0))
	box.place(cube, Vector3i(1, 1, 1))
	_expect(box.contents() == {&"puppy": 2}, "two units of one product")
	_expect(is_equal_approx(box.free_ratio(), 6.0 / 8.0), "6 of 8 cells free")
	box.fill_free_cells(3)
	_expect(is_equal_approx(box.fill_ratio(), 0.5), "3 of 6 gaps padded")
	box.fill_free_cells(3)
	_expect(is_equal_approx(box.fill_ratio(), 1.0), "every gap padded")
	_expect(is_equal_approx(box.free_ratio(), 0.0), "nothing free")


func _test_round_trip() -> void:
	var box := PackedBox.new(&"L")
	box.place(_product(&"porcelain_vase", Vector3i(1, 2, 1)), Vector3i(3, 0, 2))
	box.place(_product(&"sourdough", Vector3i(2, 1, 1)), Vector3i(0, 0, 0))
	box.fill_free_cells(5)
	box.taped = true
	box.label_order_id = &"order_7"
	box.stamps.append(&"fragile")
	var json: String = JSON.stringify(box.to_dict())
	var back: PackedBox = PackedBox.from_dict(JSON.parse_string(json))
	_expect(back.box_size == &"L", "size comes back")
	_expect(back.grid == box.grid, "every cell comes back")
	_expect(back.contents() == box.contents(), "contents come back")
	_expect(back.taped and back.label_order_id == &"order_7", "tape and label come back")
	_expect(back.stamps.size() == 1 and back.stamps[0] == &"fragile", "stamps come back")
	_expect(back.to_dict() == box.to_dict(), "the dict is stable after the trip")
	var broken: Dictionary = box.to_dict()
	broken["items"].append({"product": "hen", "origin": [0, 0, 0], "cells": [1, 1, 1]})
	_expect(
		PackedBox.from_dict(broken).items.size() == 2, "an overlapping item in a dict is dropped"
	)
