class_name PalletYardView
extends Node3D
## The pallet jack and the supplier pallets that stand on the shed's floor (expansion D-0605.b), a child of
## CompanyShed (it is redrawn with it).
##
## It only DRAWS the book of CompanyPallets (PalletJack: which pallet is on the floor and where, which one the
## jack carries) and where the jack stands, equal on every peer, so no RPC and no random roll here. The pallets
## on the truck's bed are SupplierTruckView's. A pallet on the floor has no collider (D-0605.c): it is a stand-in
## and nobody has to walk round it; what stops two from lying on each other is the host's check.
##
## The jack's home is by the dock, one step in from the gate and in reach of the truck's bed (home()): where it
## is until somebody pushes it.

signal jack_used(action: StringName, peer_id: int, from: Vector3)

## How close to the floor's south edge the jack waits (m): the same clearance as a picking cart (CompanyTuning).
const HOME_MARGIN_M: float = 0.05

## The jack drawn (PalletJackView) and the floor pallets drawn, by id.
var jack: PalletJackView
var floor_nodes: Dictionary = {}

var _stage: int = 0
var _floor_root: Node3D
## What the floor pallets were drawn from: "id@x,z" of each, sorted.
var _drawn: String = ""


## A yard for a shed of `stage`, the jack standing at its home.
static func make(stage: int) -> PalletYardView:
	var yard := PalletYardView.new()
	yard.name = "PalletYard"
	yard._stage = stage
	yard._floor_root = Node3D.new()
	yard._floor_root.name = "Floor"
	yard.add_child(yard._floor_root)
	yard.jack = PalletJackView.make(Vector3(home(stage).x, 0.0, home(stage).y))
	yard.jack.used.connect(func(action: StringName, peer_id: int, from: Vector3) -> void:
		yard.jack_used.emit(action, peer_id, from))
	yard.add_child(yard.jack)
	return yard


## Where the jack waits at the start, in the shed's frame (x, z in metres): on the dock's axis, as near the
## south wall as a picking cart may stand, so the truck's bed is in reach of the forks.
static func home(stage: int) -> Vector2:
	var axis: Vector2 = SupplierTruck.gate_span_x(stage)
	var half_depth: float = WarehouseStages.floor_size_m(stage).y * 0.5
	return Vector2((axis.x + axis.y) * 0.5, half_depth - CompanyTuning.CART_CLEARANCE_M - HOME_MARGIN_M)


## The floor of a shed of `stage` as a rect in metres in the shed's frame.
static func floor_rect(stage: int) -> Rect2:
	var size: Vector2 = WarehouseStages.floor_size_m(stage)
	return Rect2(-size * 0.5, size)


## Redraws from `pallets`: the jack where it stands (`slide` rolls it there) with the pallet it carries, and
## every pallet on the floor. A call that changes nothing changes nothing here.
func refresh(pallets: CompanyPallets, slide: bool = false) -> void:
	var at: Vector2 = pallets.jack_at if pallets.jack_at is Vector2 else home(_stage)
	jack.place_at(Vector3(at.x, 0.0, at.y), slide)
	var book: PalletJack = pallets.book
	if book.carrying != &"":
		jack.show_carried(book.places[book.carrying]["pallet"])
	else:
		jack.show_carried({})
	var on_floor: Array[StringName] = book.ids_at(PalletJack.AT_FLOOR)
	var signature: Array[String] = []
	for id: StringName in on_floor:
		var pos: Vector2 = book.places[id]["pos"]
		signature.append("%s@%.3f,%.3f" % [id, pos.x, pos.y])
	var drawn: String = ";".join(signature)
	if drawn == _drawn:
		return
	_drawn = drawn
	for child: Node in _floor_root.get_children():
		_floor_root.remove_child(child)
		child.queue_free()
	floor_nodes.clear()
	for id: StringName in on_floor:
		var place: Dictionary = book.places[id]
		var node: Node3D = PalletBox.build(place["pallet"])
		var pos: Vector2 = place["pos"]
		node.position = Vector3(pos.x, 0.0, pos.y)
		_floor_root.add_child(node)
		floor_nodes[id] = node
