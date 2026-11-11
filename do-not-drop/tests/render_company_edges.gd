extends SceneTree
## Run without --headless (revisor-visual), one PNG per street and view under user://
## (render_company_edge_<street>_<view>.png):
##   <godot> --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --script res://tests/render_company_edges.gd
## Three streets of the company map (data/world/road_graph.tres, expansion D-0304.4)
## built the way a world cell builds them (EdgePieces.build, one RouteSegment per
## piece along the Bezier, then batched as the cell is a step later: StreetBatcher,
## D-2012.2), lit like the level: an asphalt avenue in Centro
## (avenida_este_1, with a speed bump), a gravel road in Campo (camino_campo_3:
## curves, s-curve and the narrow bridge), a dirt farm track (chacra_1, mud first) and a cobbled street
## of Centro (calle_v_640_m384), each drawn with its street's surface (StreetSurface, D-0304.1b).
## Views per street: the driver's eye at its start, a 3/4 view from above the
## middle, an almost top-down view of the middle stretch and a close look at the
## first joint between two pieces (gaps, steps or kinks show there).
## And a crossing where two surfaces meet (JUNCTION, the asphalt avenue over the cobbled calle_v_640): every
## street that reaches the node, from low down and from above, each twice with the camera 0.3 m apart
## (render_company_edge_junction_*.png). One surface must show, the same in both: a toothed wedge of the
## other, or one that changes with the camera, is z-fighting (StreetSurface.LIFT).
## CI runs this (tests.yml, runtime-audit): the headless tests never compile the shader, this does
## (its `batched` branch, the one the game draws the streets with).

const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const STREETS: Array[StringName] = [&"avenida_este_1", &"camino_campo_3", &"chacra_1", &"calle_v_640_m384"]
const JUNCTION: StringName = &"c_640_0"

var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var graph := RoadGraph.load_default()
	if graph == null:
		push_error("data/world/road_graph.tres does not load")
		quit(1)
		return
	for street: StringName in STREETS:
		await _shoot(graph, street)
	await _shoot_junction(graph)
	quit(0)


func _shoot(graph: RoadGraph, street: StringName) -> void:
	var world := Node3D.new()
	root.add_child(world)
	_take_game_light(world)
	var sky := RouteSky.new()
	sky.name = "RouteSky"
	world.add_child(sky)
	var pieces: Array[RouteSegment] = EdgePieces.build(graph, street, world)
	for segment: RouteSegment in pieces:
		segment.set_physics_process(false)
	StreetBatcher.bake(world)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.far = 4000.0
	world.add_child(_camera)
	_camera.current = true
	var length: float = graph.edge_length(street)
	print("Street %s: %d pieces over %.0f m (%s)" % [
		street, pieces.size(), length, EdgePieces.signature(EdgePieces.plan(graph, street))])

	var start: Vector3 = _ground(graph, street, 1.0)
	var ahead: Vector3 = _ground(graph, street, minf(40.0, length))
	await _view(street, "driver", start + Vector3.UP * 2.4, ahead + Vector3.UP * 1.2)
	var middle: Vector3 = _ground(graph, street, length * 0.5)
	var facing: Vector2 = graph.tangent_at(street, length * 0.5)
	var side := Vector3(-facing.y, 0.0, facing.x).normalized()
	await _view(street, "three_quarter", middle + side * 35.0 + Vector3.UP * 25.0, middle)
	# Close enough that one stretch (a curve, the joints between pieces) fills the frame.
	var height: float = clampf(length * 0.25, 60.0, 160.0)
	await _view(street, "above", middle + Vector3(0.0, height, height * 0.15), middle)
	var joint: Vector3 = _ground(graph, street, _first_joint(graph, street))
	await _view(street, "joint", joint + side * 8.0 + Vector3.UP * 6.0, joint)

	world.queue_free()
	await process_frame


func _shoot_junction(graph: RoadGraph) -> void:
	var world := Node3D.new()
	root.add_child(world)
	_take_game_light(world)
	var sky := RouteSky.new()
	sky.name = "RouteSky"
	world.add_child(sky)
	for edge: RoadEdge in graph.edges_at(JUNCTION):
		for segment: RouteSegment in EdgePieces.build(graph, edge.id, world):
			segment.set_physics_process(false)
	StreetBatcher.bake(world)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.far = 4000.0
	world.add_child(_camera)
	_camera.current = true
	var point: Vector2 = graph.node_by_id(JUNCTION).position
	var centre := Vector3(point.x, 0.0, point.y)
	var cab: Vector3 = centre + Vector3(-14.0, 2.4, 11.0)
	var close: Vector3 = centre + Vector3(-5.0, 1.6, 8.0)
	var nudge := Vector3(0.3, 0.0, 0.0)
	await _view(&"junction", "cab", cab, centre)
	await _view(&"junction", "cab_nudged", cab + nudge, centre + nudge)
	await _view(&"junction", "close", close, centre)
	await _view(&"junction", "close_nudged", close + nudge, centre + nudge)
	await _view(&"junction", "above", centre + Vector3(0.0, 40.0, 6.0), centre)
	world.queue_free()
	await process_frame


## Where the second piece starts (m along the street): the first joint.
func _first_joint(graph: RoadGraph, street: StringName) -> float:
	var pieces: Array[Dictionary] = EdgePieces.plan(graph, street)
	return float(pieces[1].start) if pieces.size() > 1 else 0.0


func _ground(graph: RoadGraph, street: StringName, at: float) -> Vector3:
	var point: Vector2 = graph.point_at(street, at)
	return Vector3(point.x, 0.0, point.y)


func _view(street: StringName, view_name: String, from: Vector3, to: Vector3) -> void:
	_camera.position = from
	_camera.look_at(to)
	for _i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://render_company_edge_%s_%s.png" % [street, view_name]
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))


func _take_game_light(world: Node3D) -> void:
	var level_scene: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	var sun := level_scene.get_node(^"Sun") as DirectionalLight3D
	var environment := level_scene.get_node(^"WorldEnvironment") as WorldEnvironment
	level_scene.remove_child(sun)
	level_scene.remove_child(environment)
	level_scene.free()
	world.add_child(environment)
	world.add_child(sun)
	WorldMood.forced_label = "soleado_dia_verano"
