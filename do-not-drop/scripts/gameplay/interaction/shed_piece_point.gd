class_name ShedPiecePoint
extends Interactable
## The spot where a player uses a piece of the company's shed (expansion D-0914): a shelf, a packing
## table or the dispatch zone. CompanyShed hangs one per piece of CompanyState.layout every time it
## draws, so a piece the crew placed, moved or turned is used exactly like one of the default layout:
## same probe, same prompt, same reach, same host-side interact() (Interactable).
##
## It stands in front of the piece, one step out of its footprint, where the walkable floor is: the
## piece's own collider is solid, so a point inside it could not be seen (Player.within_reach) nor
## reached. What using it DOES (open the shelf, work the table) belongs to the stations' tasks; here
## it only says who used which piece, with `used`.

signal used(uid: StringName, role: StringName, peer_id: int)

## How far in front of the footprint the point stands, and how wide the reach around it is.
const STEP_OUT: float = 0.45
const REACH_RADIUS: float = 0.8
const PROMPT_KEYS: Dictionary = {
	&"storage": "WORLD_SHED_USE_SHELF",
	&"assembly": "WORLD_SHED_USE_TABLE",
	&"dispatch": "WORLD_SHED_USE_DISPATCH",
}

var uid: StringName = &""
var role: StringName = &""


## A point for `uid`'s piece, in the piece's own frame (the shed puts it under the same transform as
## the model, so the front is +Z): `depth` is the footprint's depth in metres. Dispatch is painted
## on the floor and does not block walking: its point stands in the middle of it.
static func make(piece_uid: StringName, piece_role: StringName, depth: float) -> ShedPiecePoint:
	var point := ShedPiecePoint.new()
	point.name = "Use_%s" % piece_uid
	point.uid = piece_uid
	point.role = piece_role
	point.position = Vector3(0.0, 1.0, 0.0 if piece_role == &"dispatch" else depth * 0.5 + STEP_OUT)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = REACH_RADIUS
	shape.shape = sphere
	point.add_child(shape)
	return point


func get_prompt() -> String:
	return tr(String(PROMPT_KEYS.get(role, "WORLD_SHED_USE_SHELF")))


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	used.emit(uid, role, int(player.get_multiplayer_authority()))
	interacted.emit(player)
