extends RefCounted
## Solid bodies the truck drives through on this peer (N-922.3).
##
## The client at the wheel simulates its own copy of the truck (N-218, vehicle_prediction.gd) in its own physics
## world. A body that stands somewhere else there than in the host's world -- the depot's staff and forklift, which
## each peer runs on its own clock; a level crossing's arms and train, which reach a client half a round trip late --
## stopped that copy where the host's truck drove on (or the other way round), and the prediction came back in a 3 m
## snap. Those bodies let the truck through instead, with a collision exception on their side (Jolt checks both
## sides, and the exception goes when they do: nothing piles up on the truck as the road streams by). The host's
## truck goes on hitting whatever only the host decides (the crossing's), never what each peer moves on its own.
##
## The truck may join the tree after the body (the route and the depot build before it, or over several frames):
## let_through() is called every physics tick until it says it found one.

const GROUP: StringName = &"vehicle"


## Adds every truck in the tree as a collision exception of each of `bodies`. False while there is no truck yet.
static func let_through(bodies: Array, tree: SceneTree) -> bool:
	if tree == null:
		return false
	var found: bool = false
	for truck: Node in tree.get_nodes_in_group(GROUP):
		var truck_body := truck as PhysicsBody3D
		if truck_body == null:
			continue
		found = true
		for body: Variant in bodies:
			if not is_instance_valid(body):
				continue
			var physics_body := body as PhysicsBody3D
			if physics_body != null and physics_body != truck_body:
				physics_body.add_collision_exception_with(truck_body)
	return found
