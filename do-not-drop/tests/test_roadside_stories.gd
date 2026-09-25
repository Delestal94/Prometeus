extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_roadside_stories.gd
##
## Stories by the road (N-602, roadside_story.gd, RouteDresser._dress_roadside_stories):
## - rare: never two within STORY_MIN_GAP (800 m) of road, none in the first
##   STORY_START metres;
## - all three kinds turn up across seeds: the competition's van in the
##   ditch with its parcels strewn about, a hen next to her broken box, the
##   "entregamos (casi) todo" billboard;
## - off the asphalt, the van's crash never in a village and the billboard
##   never in the forest; what the truck could hit (van, billboard legs) is solid;
## - the same seed tells the same stories in the same spots.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var kinds_seen: Dictionary = {}
	var total: int = 0
	for seed_value: int in [4242, 777, 11, 90210, 31337, 5, 606, 2024]:
		network.set(&"world_seed", seed_value)
		network.set(&"world_house_count", 4)
		var route: Node3D = await _build()
		var dresser: RouteDresser = route.get(&"dresser")
		var stories: Array[Node3D] = []
		stories.assign(dresser.roadside_stories)
		var last: float = -INF
		for story: Node3D in stories:
			var distance: float = float(story.get_meta(&"story_distance"))
			_expect(distance >= RouteDresser.STORY_START, "seed %d: no story in the first %.0f m (one at %.0f m)" % [seed_value, RouteDresser.STORY_START, distance])
			_expect(distance - last >= RouteDresser.STORY_MIN_GAP, "seed %d: stories at least %.0f m apart (%.0f after %.0f)" % [seed_value, RouteDresser.STORY_MIN_GAP, distance, last])
			last = distance
			var kind: int = int(story.get(&"kind"))
			kinds_seen[kind] = int(kinds_seen.get(kind, 0)) + 1
			total += 1
			var p: Vector3 = route.to_local(story.global_position)
			var terrain: Node = route.get(&"terrain")
			var edge: float = terrain.nearest(Vector2(p.x, p.z)).x - float(story.get_meta(&"reach"))
			_expect(edge >= 6.5, "seed %d: the story stays off the asphalt (%.1f m from the centreline)" % [seed_value, edge])
			# The zone of the stretch it stands by, as the dresser judged it.
			var zone: String = str(story.get_meta(&"zone", ""))
			match kind:
				RoadsideStory.Kind.VAN_SPILL:
					_expect(zone != "village" and zone != "", "seed %d: the van's crash is out of town (%s)" % [seed_value, zone])
					_expect(story.find_child("CompetitorVan", true, false) != null and story.find_child("BackDoorOpen", true, false) != null,
						"seed %d: the competition's van is there with its back door open" % seed_value)
					_expect(story.find_children("SpilledBox*", "", true, false).size() >= 4, "seed %d: its parcels lie strewn about" % seed_value)
					_expect(story.find_child("VanCollision", true, false) is StaticBody3D, "seed %d: the crashed van is solid" % seed_value)
					# Against the real ground under each end, not the story's
					# own level: beside the road it slopes.
					var van := story.find_child("CompetitorVan", true, false) as Node3D
					var nose: float = _above_ground(route, terrain, van.to_global(Vector3(0.0, 0.0, RoadsideStory.VAN_NOSE_Z)))
					var tail: float = _above_ground(route, terrain, van.to_global(Vector3(0.0, 0.0, RoadsideStory.VAN_TAIL_Z)))
					_expect(nose < -0.2 and tail > 0.2, "seed %d: the van's nose is dug into the ground and its tail lifted (nose %.2f m, tail %.2f m over the ground)" % [seed_value, nose, tail])
					for box: Node in story.find_children("SpilledBox*", "", true, false):
						var gap: float = _above_ground(route, terrain, (box as Node3D).global_position)
						_expect(absf(gap) < 0.12, "seed %d: %s rests on the ground (%.2f m off it)" % [seed_value, box.name, gap])
				RoadsideStory.Kind.HEN:
					var hen := story.find_child("Hen", true, false) as Node3D
					_expect(hen != null and story.find_child("BrokenBox", true, false) != null, "seed %d: a hen next to her broken box" % seed_value)
					if hen != null:
						var intact := hen.find_child("Intact", true, false) as Node3D
						_expect(intact != null and intact.visible, "seed %d: the hen shows the live bird" % seed_value)
				RoadsideStory.Kind.BILLBOARD:
					_expect(zone != "forest" and zone != "", "seed %d: the billboard stands out of the forest (%s)" % [seed_value, zone])
					var slogan := story.find_child("Slogan", true, false) as Label3D
					_expect(slogan != null and slogan.text.contains("casi"), "seed %d: the billboard carries the slogan" % seed_value)
					_expect(story.find_child("BillboardCollision", true, false) is StaticBody3D, "seed %d: the billboard's legs are solid" % seed_value)
					var panel_width: float = RoadsideStory.BILLBOARD_SIZE.x - 0.3
					for label_name: String in ["Brand", "Slogan"]:
						var label := story.find_child(label_name, true, false) as Label3D
						var width: float = label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
						_expect(absf(label.position.x) + width * 0.5 < panel_width * 0.5, "seed %d: the %s fits on the panel (%.1f m of %.1f)" % [seed_value, label_name, width, panel_width])
					var parcel := story.find_child("BillboardParcel", true, false) as Node3D
					_expect(parcel.position.y >= RoadsideStory.BILLBOARD_HEIGHT + RoadsideStory.BILLBOARD_SIZE.y - 0.01,
						"seed %d: the parcel sits on the top edge, not over the lettering" % seed_value)
		var signature: Array = _signature(route, stories)
		route.free()
		await process_frame
		var again: Node3D = await _build()
		var again_stories: Array[Node3D] = []
		again_stories.assign((again.get(&"dresser") as RouteDresser).roadside_stories)
		_expect(signature == _signature(again, again_stories), "seed %d: the same seed tells the same stories in the same spots" % seed_value)
		again.free()
		await process_frame
	# A longer translation of the slogan is set smaller, not left to overflow.
	var long_line: String = "entregamos casi todo, casi siempre, casi enteros"
	var fitted: int = RoadsideStory.fit_font_size(long_line, 80, 7.2)
	_expect(fitted < 80 and RoadsideStory.FONT.get_string_size(long_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x * RoadsideStory.BILLBOARD_PIXEL_SIZE <= 7.2,
		"A slogan too long for the billboard is set smaller until it fits (%d px)" % fitted)
	_expect(kinds_seen.size() == 3, "Every kind of story turns up across seeds (%s)" % kinds_seen)
	_expect(total >= 6, "Stories do turn up (%d over 8 routes)" % total)

	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: roadside stories are rare, varied, off the road, solid where it matters, the same for every peer")
	quit(_failures)


func _build() -> Node3D:
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate()
	route.set(&"batch_dressing", false)
	root.add_child(route)
	await process_frame
	return route


func _signature(route: Node3D, stories: Array[Node3D]) -> Array:
	var signature: Array = []
	for story: Node3D in stories:
		signature.append([int(story.get(&"kind")), route.to_local(story.global_position).snapped(Vector3.ONE * 0.01)])
	return signature


## How far `point` is above the terrain under it (negative: buried).
func _above_ground(route: Node3D, terrain: Node, point: Vector3) -> float:
	var local: Vector3 = route.to_local(point)
	return local.y - float(terrain.call(&"height_at", local))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
