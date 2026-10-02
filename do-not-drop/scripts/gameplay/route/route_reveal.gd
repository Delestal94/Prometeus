extends RefCounted
## The route's first draw in pieces, for the loading cover (N-408c, like the depot's
## reveal_steps()): SceneLoader runs one step per frame, so uploading and drawing
## the whole route for the first time doesn't land in one 150-220 ms frame. The
## pieces are the route's own children in the order the build made them (the
## terrain, then the road leg by leg, then the goal, the sky...), with the terrain
## tiles and the batched dressing's cells as pieces of their own, since each of
## those two is one child holding a large share of the draw.

## How many frames the route's first draw is spread over.
const PARTS: int = 12
## Children whose own children are the pieces: the batched dressing's cells
## (DressingBatcher.bake) and, by node, the terrain's tiles.
const SPLIT_NAMES: Array[StringName] = [&"BatchedDressing"]


## Hides what it will show (only what is visible now) and returns the steps; the
## first one shows `route` itself. Call it once the route is built, while it is hidden.
static func steps(route: Node3D, terrain: Node3D) -> Array[Callable]:
	var pieces: Array[Node3D] = []
	for child: Node in route.get_children():
		if child == terrain or SPLIT_NAMES.has(child.name):
			for grandchild: Node in child.get_children():
				_add_piece(pieces, grandchild)
		else:
			_add_piece(pieces, child)
	for piece: Node3D in pieces:
		piece.visible = false
	var result: Array[Callable] = []
	var parts: int = clampi(pieces.size(), 1, PARTS)
	for part: int in range(parts):
		var members: Array[Node3D] = pieces.slice(pieces.size() * part / parts, pieces.size() * (part + 1) / parts)
		result.append(_show.bind(route, members, part == 0))
	return result


static func _add_piece(pieces: Array[Node3D], node: Node) -> void:
	var piece := node as Node3D
	if piece != null and piece.visible:
		pieces.append(piece)


static func _show(route: Node3D, members: Array[Node3D], with_route: bool) -> void:
	if with_route and is_instance_valid(route):
		route.visible = true
	for member: Node3D in members:
		if is_instance_valid(member):
			member.visible = true
