class_name PickingCartPoint
extends Interactable
## A spot where a player works a picking cart (expansion D-0610.b): the platform (load what is in the hands,
## or unload into them when they are empty) and the handle (push). PickingCartView hangs one of each on every
## cart, so both take the same probe, prompt, reach and host-side interact() as any Interactable.
##
## It only says who used which cart and how, with `used`: what that DOES (the units_store / units_take /
## cart_push request to the host) is PickingCartUse's, driven by CompanyRoot on the host.

signal used(cart_id: StringName, action: StringName, peer_id: int, from: Vector3)

const ACTION_LOAD: StringName = &"load"
const ACTION_PUSH: StringName = &"push"
const PROMPT_KEYS: Dictionary = {
	ACTION_LOAD: "WORLD_SHED_USE_CART",
	ACTION_PUSH: "WORLD_SHED_PUSH_CART",
}

var cart_id: StringName = &""
var action: StringName = ACTION_LOAD


## A point for cart `id` at `at` (the cart's own frame), `radius` wide.
static func make(id: StringName, point_action: StringName, at: Vector3, radius: float) -> PickingCartPoint:
	var point := PickingCartPoint.new()
	point.name = "Use_%s_%s" % [id, point_action]
	point.cart_id = id
	point.action = point_action
	point.position = at
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	point.add_child(shape)
	return point


func get_prompt() -> String:
	return tr(String(PROMPT_KEYS.get(action, "WORLD_SHED_USE_CART")))


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var from: Vector3 = (player as Node3D).global_position if player is Node3D else global_position
	used.emit(cart_id, action, int(player.get_multiplayer_authority()), from)
	interacted.emit(player)
