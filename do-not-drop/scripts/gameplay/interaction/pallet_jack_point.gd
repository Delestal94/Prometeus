class_name PalletJackPoint
extends Interactable
## A spot where a player works the pallet jack (expansion D-0605.b): the forks (pick a pallet up, or put the
## one it carries down) and the handle (push it). PalletJackView hangs one of each on the jack, so both take the
## same probe, prompt, reach and host-side interact() as any Interactable.
##
## It only says who used the jack and how, with `used`: what that DOES (the jack_pick / jack_put / jack_push
## request to the host) is PalletJackUse's, driven by CompanyRoot on the host.

signal used(action: StringName, peer_id: int, from: Vector3)

const ACTION_WORK: StringName = &"work"
const ACTION_PUSH: StringName = &"push"
const PROMPT_KEYS: Dictionary = {
	ACTION_WORK: "WORLD_SHED_USE_JACK",
	ACTION_PUSH: "WORLD_SHED_PUSH_JACK",
}

var action: StringName = ACTION_WORK


## A point for `point_action` at `at` (the jack's own frame), `radius` wide.
static func make(point_action: StringName, at: Vector3, radius: float) -> PalletJackPoint:
	var point := PalletJackPoint.new()
	point.name = "Use_%s" % point_action
	point.action = point_action
	point.position = at
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	point.add_child(shape)
	return point


func get_prompt() -> String:
	return tr(String(PROMPT_KEYS.get(action, "WORLD_SHED_USE_JACK")))


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var from: Vector3 = (player as Node3D).global_position if player is Node3D else global_position
	used.emit(action, int(player.get_multiplayer_authority()), from)
	interacted.emit(player)
