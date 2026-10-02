class_name RouteSignage
extends RefCounted
## What stands at the roadside to be read: hazard and delivery signs,
## guardrails and roadworks, town-limit signs as the road enters and leaves a
## village (N-601), the little roadside stories (N-602), and each house's
## yard settled onto the ground. Explicit features: they run before the rule
## table and claim their space first.

const SIGN_DIR: String = "res://assets/models/environment/signs/"
## Which warning goes up in front of which hazard. Straight roads get none:
## a sign that means "nothing ahead" teaches players to ignore signs.
const HAZARD_SIGNS: Dictionary = {
	"CurveSegment": "sm_env_sign_curve.glb",
	"SCurveSegment": "sm_env_sign_curve.glb",
	"SpeedBumpSegment": "sm_env_sign_speed_bump.glb",
	"NarrowBridgeSegment": "sm_env_sign_narrow_bridge.glb",
	"ChicaneSegment": "sm_env_sign_narrow_bridge.glb",
	"GravelSegment": "sm_env_sign_gravel.glb",
	# No mud sign model yet (needs the PC): the gravel one stands in, and the
	# segment's own board says what it is (mud_segment.gd).
	"MudSegment": "sm_env_sign_gravel.glb",
	"ConstructionZoneSegment": "sm_env_sign_roadworks.glb",
}
const DELIVERY_SIGN: String = SIGN_DIR + "sm_env_sign_delivery_ahead.glb"
## Town-limit signs (TownSign, N-601): sampled every this many metres along
## the road, standing this far right of the centreline.
const TOWN_SIGN_STEP: float = 4.0
const TOWN_SIGN_LATERAL: float = 9.4
## Roadside stories (RoadsideStory, N-602): at most one per STORY_MIN_GAP
## metres of road, none before STORY_START; STORY_LATERAL is how far the
## scene's near edge stands from the centreline.
const STORY_MIN_GAP: float = 800.0
const STORY_START: float = 250.0
const STORY_CHANCE: float = 0.5
const STORY_LATERAL: Vector2 = Vector2(10.0, 14.0)
const SIGN_LATERAL: float = 7.8
## The warning stands this far before the hazard's first metre.
const SIGN_LEAD: float = 6.0
const GUARDRAIL: String = RouteDresser.PROPS + "sm_env_prop_guardrail.glb"
const GUARDRAIL_LATERAL: float = 7.4


var _dresser: RouteDresser
var _placement: RoutePlacement
var _route: Node3D
var _terrain: Node
var _seed: int
## Every town-limit sign put up, entries and exits, in road order (N-601).
var town_signs: Array[Node3D] = []
## Every roadside story put up (N-602), in road order.
var roadside_stories: Array[Node3D] = []


func _init(dresser: RouteDresser, placement: RoutePlacement, route: Node3D, terrain: Node, seed_value: int) -> void:
	_dresser = dresser
	_placement = placement
	_route = route
	_terrain = terrain
	_seed = seed_value


func dress_signs(segment: RouteSegment) -> void:
	var sign_file: String = HAZARD_SIGNS.get(segment.get_script().get_global_name(), "")
	if sign_file != "":
		# The curve arrow is modelled bending to the driver's right; mirror it
		# for a left-hander, reading the bend off where the segment actually
		# ends rather than trusting the sign convention of turn_deg.
		var mirror: bool = segment is CurveSegment and segment.exit_offset.x < 0.0
		place_sign(segment, SIGN_DIR + sign_file, 1.0, SIGN_LEAD, mirror, &"hazard_sign")
	if segment.has_meta(&"delivery_sign_side"):
		# Inside the segment rather than ahead of it, so it never shares a
		# corner with a hazard sign.
		place_sign(segment, DELIVERY_SIGN, float(segment.get_meta(&"delivery_sign_side")),
				-minf(12.0, segment.length * 0.4), false, &"delivery_sign")


## A named sign where the road enters each village and a crossed-out one
## where it leaves (N-601): walks the road in TOWN_SIGN_STEP steps and puts
## one up at every change into or out of the VILLAGE zone. A route that ends
## inside a village (the goal next to the last house) gets no exit sign.
## A sign whose spot is taken (a service station's yard, N-110) goes up at the
## next free step on the same side of the boundary; a village entered again
## before its exit sign found room just carries on, so a village is always
## left before the next one is entered.
func dress_town_signs(segments: Array) -> void:
	var names: Array[String] = TownSign.names_for_seed(_seed)
	var town: int = -1
	var inside: bool = false
	var last_inside: Array = []
	var entry_owed: bool = false
	var exit_owed: bool = false
	for segment: RouteSegment in segments:
		var start_distance: float = float(segment.get_meta(&"route_distance", 0.0))
		for slot: Transform3D in segment.get_dressing_slots(TOWN_SIGN_STEP):
			var now_inside: bool = _dresser.zone_at(segment.transform * slot.origin,
					start_distance - slot.origin.z) == RouteDresser.Zone.VILLAGE
			if now_inside and not inside:
				if exit_owed:
					exit_owed = false
				else:
					town += 1
					entry_owed = not _place_town_sign(segment, slot, names[town % names.size()], false)
			elif now_inside and entry_owed:
				entry_owed = not _place_town_sign(segment, slot, names[town % names.size()], false)
			elif inside and not now_inside and not last_inside.is_empty() and not entry_owed:
				exit_owed = not _place_town_sign(last_inside[0], last_inside[1], names[town % names.size()], true)
			elif not now_inside and exit_owed:
				exit_owed = not _place_town_sign(segment, slot, names[town % names.size()], true)
			if not now_inside:
				entry_owed = false
			inside = now_inside
			if now_inside:
				last_inside = [segment, slot]


## On the driver's right, facing the traffic, through the same checks as any
## sign; stepped further out if the first spot is taken (false if none was free). Kept as a node (it
## builds its own board and text), so the batcher leaves it alone.
func _place_town_sign(segment: RouteSegment, slot: Transform3D, town_name: String, is_exit: bool) -> bool:
	var reach: float = TownSign.POST_GAP * 0.5 + 0.1
	for lateral: float in [TOWN_SIGN_LATERAL, TOWN_SIGN_LATERAL + 1.0, TOWN_SIGN_LATERAL + 2.0]:
		var xform: Transform3D = slot * Transform3D(Basis.IDENTITY, Vector3(lateral, 0.0, 0.0))
		var p: Vector3 = segment.transform * xform.origin
		if _placement.misfit(p, reach, 6.8, 1.0, true, &"town_sign", 0.0, TownSign.BOARD_SIZE.x * 0.5) != &"":
			continue
		var sign_node := TownSign.new()
		sign_node.name = "TownExit" if is_exit else "TownEntry"
		sign_node.town_name = town_name
		sign_node.is_exit = is_exit
		sign_node.transform = xform
		_placement.group(segment, "RoadsideDressing").add_child(sign_node, true)
		_placement.settle(sign_node, p)
		sign_node.set_meta(&"rule", &"town_sign")
		sign_node.set_meta(&"reach", reach)
		sign_node.set_meta(&"footprint", TownSign.BOARD_SIZE.x * 0.5)
		sign_node.set_meta(&"solid", true)
		_placement.occupy(p, TownSign.BOARD_SIZE.x * 0.5)
		town_signs.append(sign_node)
		_placement.count(&"town_sign")
		return true
	return false


## Little stories by the road (RoadsideStory, N-602): at most one every
## STORY_MIN_GAP metres, none in the first STORY_START, each a 50/50 draw per
## segment once the gap has passed, dealt from a seeded deck so a route shows
## each kind before repeating one. The competition's crash stays out of the
## villages; the billboard stays out of the forest (nobody rents one there).
func dress_roadside_stories(segments: Array) -> void:
	var deck: Array[int] = [RoadsideStory.Kind.VAN_SPILL, RoadsideStory.Kind.HEN, RoadsideStory.Kind.BILLBOARD]
	var shuffle := RandomNumberGenerator.new()
	shuffle.seed = hash([_seed, &"story_deck"])
	for i: int in range(deck.size() - 1, 0, -1):
		var j: int = shuffle.randi_range(0, i)
		var swap: int = deck[i]
		deck[i] = deck[j]
		deck[j] = swap
	var next: int = 0
	var last_distance: float = STORY_START - STORY_MIN_GAP
	for index: int in range(segments.size()):
		var segment: RouteSegment = segments[index]
		if segment is TunnelSegment or segment is NarrowBridgeSegment or segment is RailCrossingSegment:
			continue
		var distance: float = float(segment.get_meta(&"route_distance", 0.0))
		if distance - last_distance < STORY_MIN_GAP:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_seed, index, &"roadside_story"])
		var roll: float = rng.randf()
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var lateral: float = rng.randf_range(STORY_LATERAL.x, STORY_LATERAL.y)
		var story_seed: int = rng.randi()
		if roll > STORY_CHANCE:
			continue
		var kind: int = deck[next % deck.size()]
		var middle := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -segment.length * 0.5))
		var zone: int = _dresser.zone_at(segment.transform * middle.origin, distance + segment.length * 0.5)
		var van_in_village: bool = kind == RoadsideStory.Kind.VAN_SPILL and zone == RouteDresser.Zone.VILLAGE
		var billboard_in_forest: bool = kind == RoadsideStory.Kind.BILLBOARD and zone == RouteDresser.Zone.FOREST
		if van_in_village or billboard_in_forest:
			continue
		if _place_story(segment, middle, kind, side, lateral, story_seed, zone):
			next += 1
			last_distance = distance


func _place_story(segment: RouteSegment, slot: Transform3D, kind: int, side: float, lateral: float, story_seed: int,
		zone: int) -> bool:
	var reach: float = float(RoadsideStory.REACH[kind])
	var footprint: float = float(RoadsideStory.FOOTPRINT[kind])
	var distance_out: float = lateral + reach
	# A billboard turns a little toward the traffic coming at it; the rest
	# face wherever their scatter says (RoadsideStory builds them).
	var basis := Basis.IDENTITY
	if kind == RoadsideStory.Kind.BILLBOARD:
		basis = Basis(Vector3.UP, -side * 0.35)
	var xform: Transform3D = slot * Transform3D(basis, Vector3(side * distance_out, 0.0, 0.0))
	var p: Vector3 = segment.transform * xform.origin
	if _placement.misfit(p, reach, 6.8, 0.3, true, &"roadside_story", 0.0, footprint) != &"":
		return false
	if _placement.in_zones(_placement.sight_zones, p, footprint):
		_placement.reject(&"roadside_story", &"sight_line")
		return false
	var story := RoadsideStory.new()
	story.name = "RoadsideStory"
	story.kind = kind
	story.story_seed = story_seed
	story.transform = xform
	_placement.group(segment, "RoadsideDressing").add_child(story, true)
	# Down onto the ground by every foot (the van's wheels, the strewn boxes).
	_placement.settle(story, p)
	# Then each of its pieces on the ground under it (the slope beside a road).
	story.fit_to_ground(func(local: Vector3) -> float:
		var q: Vector3 = _route.to_local(story.to_global(local))
		return story.to_local(_route.to_global(Vector3(q.x, _terrain.height_at(q), q.z))).y)
	story.set_meta(&"rule", &"roadside_story")
	story.set_meta(&"reach", reach)
	story.set_meta(&"footprint", footprint)
	story.set_meta(&"solid", true)
	story.set_meta(&"story_distance", float(segment.get_meta(&"route_distance", 0.0)))
	story.set_meta(&"zone", RouteDresser.ZONE_NAMES[zone])
	_placement.occupy(p, footprint)
	roadside_stories.append(story)
	_placement.count(&"roadside_story")
	return true


## Signs are authored facing -Z; half a turn makes them face the driver
## coming up the road (who travels toward -Z). `distance` is along the
## segment's real path (negative = into it, positive = before it), read off
## its dressing slots so a sign inside a curve follows the bend instead of
## standing where a straight road would have been. If the ideal spot is
## taken or too tight, it steps further out before giving up.
func place_sign(segment: RouteSegment, path: String, side: float, distance: float, mirror: bool,
		id: StringName) -> void:
	var slot: Transform3D = Transform3D.IDENTITY
	var along: float = distance
	if distance < 0.0:
		var slots: Array[Transform3D] = segment.get_dressing_slots(2.0)
		var index: int = clampi(roundi(-distance / 2.0), 0, slots.size() - 1)
		slot = slots[index]
		along = 0.0
	var basis := Basis(Vector3.UP, PI)
	if mirror:
		basis = basis * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	for lateral: float in [SIGN_LATERAL, SIGN_LATERAL + 0.9, SIGN_LATERAL + 1.9]:
		var xform: Transform3D = slot * Transform3D(basis, Vector3(side * lateral, 0.0, along))
		if _placement.try_place(segment, "RoadsideDressing", path, xform,
				{"id": id, "radius": 0.5, "clearance": 6.8, "max_slope": 1.0, "solid": true, "tilt": true,
						"see_through": true}) != null:
			return


func dress_barriers(segment: RouteSegment) -> void:
	if segment is CurveSegment:
		_place_guardrails(segment)
	# ConstructionZoneSegment owns its lane closure, including its imported
	# cones/barriers. Adding roadside dressing here created a second set on
	# top of it and made the road unreadable.


## Along the outside of every real bend -- the side a van that takes it too
## fast leaves the road on. Authored along X with the reflector on -Z; a
## quarter turn lays it along the road, reflector toward the asphalt.
func _place_guardrails(segment: RouteSegment) -> void:
	var outer: float = -signf(segment.exit_offset.x)
	if outer == 0.0:
		return
	for slot: Transform3D in segment.get_dressing_slots(4.0):
		var xform: Transform3D = slot * Transform3D(Basis(Vector3.UP, outer * PI * 0.5),
				Vector3(outer * GUARDRAIL_LATERAL, 0.0, -2.0))
		_placement.try_place(segment, "RoadsideDressing", GUARDRAIL, xform,
			{"id": &"guardrail", "radius": 0.3, "footprint": 1.8, "clearance": 6.6, "max_slope": 1.0, "solid": true,
					"tilt": true})


## Cones and the barrier stand right at the edge of the closed lane (that's
## the point of them); the crew's pallet and crate wait behind it.
func _place_roadworks(segment: RouteSegment) -> void:
	var slots: Array[Transform3D] = segment.get_dressing_slots(2.2)
	var edge: Dictionary = {"id": &"roadworks", "radius": 0.3, "clearance": 5.8, "max_slope": 1.0, "solid": true}
	# The barrier goes first and claims its whole 2.2 m board (feet at
	# +-0.85), so the cones -- which used to share its spot -- line up behind
	# it instead of standing inside its legs.
	if not slots.is_empty():
		var barrier: Dictionary = edge.duplicate()
		barrier["footprint"] = 1.2
		_placement.try_place(segment, "RoadsideDressing", RouteDresser.PROPS + "sm_env_prop_road_barrier.glb",
				slots[0] * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(6.4, 0.0, -1.2)), barrier)
	for index: int in range(mini(4, slots.size() - 2)):
		_placement.try_place(segment, "RoadsideDressing", RouteDresser.PROPS + "sm_env_prop_traffic_cone.glb",
				slots[index + 2] * Transform3D(Basis.IDENTITY, Vector3(6.4, 0.0, 0.0)), edge)
	var mid: float = -segment.length * 0.5
	var crew: Dictionary = {"id": &"roadworks", "radius": 0.8, "clearance": 7.0, "max_slope": 0.4, "solid": true,
			"tilt": true}
	_placement.try_place(segment, "RoadsideDressing", RouteDresser.PROPS + "sm_env_prop_pallet.glb",
			Transform3D(Basis(Vector3.UP, 0.2), Vector3(8.4, 0.0, mid + 1.6)), crew)
	_placement.try_place(segment, "RoadsideDressing", RouteDresser.PROPS + "sm_env_prop_wooden_crate.glb",
			Transform3D(Basis(Vector3.UP, -0.15), Vector3(8.2, 0.0, mid - 0.8)), crew)


## Yard pieces were laid out by route.gd from the house's own bounds. The
## porch ones (meta on_porch) belong to the house and ride on its porch
## deck; everything else in the lot has to pass the same checks as any
## roadside prop, or it's dropped -- which is what kept a fence off the
## asphalt when a house was dealt a tight spot.
func settle_yard(house: Node3D) -> void:
	var yard: Node = house.get_node_or_null(^"Yard")
	if yard == null:
		return
	var pieces: Array = yard.get_children()
	# Biggest first, so a barn keeps its spot and a fence panel gives way.
	pieces.sort_custom(func(a: Node,
			b: Node) -> bool: return float(a.get_meta(&"footprint", 0.0)) > float(b.get_meta(&"footprint", 0.0)))
	for piece: Node3D in pieces:
		if piece.get_meta(&"on_porch", false):
			_placement.count(&"yard")
			continue
		var p: Vector3 = _route.to_local(piece.global_position)
		var radius: float = float(piece.get_meta(&"footprint", 0.8))
		if _placement.misfit(p, radius, 7.2, 0.45, false, &"yard", 0.0) != &"":
			piece.free()
			continue
		_placement.settle(piece, p)
		piece.set_meta(&"rule", &"yard")
		piece.set_meta(&"reach", radius)
		piece.set_meta(&"solid", true)
		_placement.occupy(p, radius)
		_placement.count(&"yard")
