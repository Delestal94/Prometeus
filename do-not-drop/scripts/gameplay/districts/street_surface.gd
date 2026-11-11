class_name StreetSurface
extends RefCounted
## The look of the company map's streets (expansion D-0304.1b): each piece EdgePieces lays builds its
## roadway and verge as RouteSegment's flat colour boxes (modules/route_gen, which knows nothing of
## surfaces); this dresses them in shaders/street_surface.gdshader by the street's RoadEdge.surface:
## asphalt, gravel, dirt (a farm track with ruts and grass on the crown) or cobble (granite setts).
##
## - The roadway: every box drawn in RouteSegment.ROAD or GravelSegment.GRAVEL (StraightSegment's and
##   the other pieces' `Road`, each chord of a CurveSegment, a speed bump's or a chicane's road). A
##   piece that is a surface of its own keeps it: a GravelSegment is gravel on any street, and a
##   MudSegment's mud (mud_ground.gdshader) is not touched.
## - The verge: every box in RouteSegment.SHOULDER (the `Ground` under the roadway) gets the grass.
## - Lane lines (StraightSegment's EdgeMarking / CenterMarking, CurveSegment's EdgeLine: every mesh in
##   RouteSegment.MARKING or the centre line's grey) only on asphalt: on gravel, dirt and cobble they are
##   hidden. By colour, not by name: a piece's second line of the same name is renamed by Godot. What is
##   not a lane line stays on every surface: a rail crossing's stop lines, the line to stop at before
##   the train (RailCrossingSegment.STOP_LINE_GROUP).
## Where two streets cross their boxes overlap with the same top: each surface is drawn a few millimetres
## over the one below it (LIFT, the shader's `lift`), so the crossing shows one of them, asphalt over
## cobble over gravel over dirt, instead of a flickering wedge of both. Only the drawing moves.
##
## The boxes, their collision and their size stay (the roadway is still the 12 m box Centro's sidewalks
## are laid against, CentroDecor.ROADWAY_HALF_WIDTH). One ShaderMaterial per surface for the whole map,
## shared by every piece (material()).
##
## What a street looks like is what it does (the D-0304 review): the grip follows the drawn surface. A
## piece of a street that is loose (GRIP) gets a GripArea over its visible roadway, so a gravel street's
## curve holds like its gravel patches and a dirt track's straight like dirt; a GravelSegment and a
## MudSegment bring their own. A bridge's deck is not the street's surface: it has no area. The bodies of
## the roadway and the verge carry the same fact for a runner: AUDIO_META (the footsteps,
## GelPlayerAudio._surface_from_collider) and ROUGHNESS_META (the trip, PlayerSprint.ground_roughness).

const SHADER: Shader = preload("res://shaders/street_surface.gdshader")
const DETAIL_FORMAT: String = "res://assets/textures/detail/tx_detail_%s_512.png"
## RoadEdge.surface -> the shader's `surface`.
const SURFACES: Dictionary = {&"asphalt": 0, &"gravel": 1, &"dirt": 2, &"cobble": 3}
## The ground either side of the roadway (the shader's surface 4).
const VERGE: StringName = &"verge"
const VERGE_INDEX: int = 4
## A street whose surface is not in SURFACES is drawn as this.
const FALLBACK: StringName = &"asphalt"
## Surfaces whose pieces keep their painted lane lines.
const MARKED: Array[StringName] = [&"asphalt"]
## The colours a piece paints its lane lines with: RouteSegment.MARKING and StraightSegment's centre line.
const LINE_COLOURS: Array[Color] = [RouteSegment.MARKING, Color("8c9994")]
## How far over the box's top each surface is drawn (m): where two streets cross, the higher one shows. With
## the shader's lift_by_heading on top it stays under the lowest lane line (StraightSegment's CenterMarking
## starts 2.2 cm over the road); the verge's box is well under the roadway already.
const LIFT: Dictionary = {&"asphalt": 0.016, &"cobble": 0.012, &"gravel": 0.008, &"dirt": 0.004}
## wheel_friction_slip on a street whose surface is loose (the wheels' own 3.5 elsewhere). Gravel is
## GravelSegment.reduced_friction_slip; packed earth holds better than that and than a mud pit (1.2).
const GRIP: Dictionary = {&"gravel": 1.1, &"dirt": 1.6}
## The name of the GripArea on a piece.
const GRIP_NODE: StringName = &"SurfaceGrip"
## Metadata of a roadway or verge body: the footsteps' surface (GelSounds.SURFACE_NAMES).
const AUDIO_META: StringName = &"gel_audio_surface"
## Metadata of a roadway or verge body: how rough it is underfoot, on Route.ground_roughness()'s scale.
const ROUGHNESS_META: StringName = &"ground_roughness"
## Each surface's [AUDIO_META, ROUGHNESS_META]. Setts are hard underfoot and a little uneven; the synth has
## no footstep of their own, so they sound like the road.
const UNDERFOOT: Dictionary = {
	&"asphalt": [&"road", 0.0], &"cobble": [&"road", 0.1], &"gravel": [&"gravel", 1.0], &"dirt": [&"soft", 0.5],
	&"verge": [&"soft", 0.25],
}
## The detail maps the shader reads, by uniform prefix (<name>_detail).
const DETAILS: Array[String] = ["asphalt", "gravel", "earth", "stone", "grass"]

static var _materials: Dictionary = {}


## The shared material of `surface` (a RoadEdge.surface, or VERGE).
static func material(surface: StringName) -> ShaderMaterial:
	var key: StringName = surface if surface == VERGE or SURFACES.has(surface) else FALLBACK
	if not _materials.has(key):
		var made := ShaderMaterial.new()
		made.shader = SHADER
		made.set_shader_parameter(&"surface", VERGE_INDEX if key == VERGE else int(SURFACES[key]))
		made.set_shader_parameter(&"lift", float(LIFT.get(key, 0.0)))
		for detail: String in DETAILS:
			var path: String = DETAIL_FORMAT % detail
			if ResourceLoader.exists(path):
				made.set_shader_parameter(StringName(detail + "_detail"), load(path))
		_materials[key] = made
	return _materials[key] as ShaderMaterial


## Makes every surface's material now (its detail maps load with it): a level calls it while it is being
## built, so the first piece of a street does not load them in the frame its cell enters the tree.
static func warm() -> void:
	for surface: StringName in SURFACES:
		material(surface)
	material(VERGE)


## The surface a piece is drawn with on a street of `street_surface`: its own when it is a surface of its own.
static func surface_of(segment: RouteSegment, street_surface: StringName) -> StringName:
	if segment is GravelSegment:
		return &"gravel"
	return street_surface if SURFACES.has(street_surface) else FALLBACK


## Dresses `segment` for a street of `street_surface`. A piece builds its boxes in _ready(): one that
## is not built yet (not in the tree) is dressed as soon as it is.
static func dress(segment: RouteSegment, street_surface: StringName) -> void:
	if segment.is_node_ready():
		apply(segment, street_surface)
	else:
		segment.ready.connect(func() -> void: apply(segment, street_surface), CONNECT_ONE_SHOT)


## Dresses a built piece now: {road, verge, lines_hidden} (how many meshes of each it changed).
static func apply(segment: RouteSegment, street_surface: StringName) -> Dictionary:
	var surface: StringName = surface_of(segment, street_surface)
	var road: ShaderMaterial = material(surface)
	var verge: ShaderMaterial = material(VERGE)
	var marked: bool = MARKED.has(surface)
	var done: Dictionary = {"road": 0, "verge": 0, "lines_hidden": 0}
	var roadway: Array[MeshInstance3D] = []
	var pending: Array[Node] = [segment]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		var mesh := node as MeshInstance3D
		if mesh == null or not (mesh.material_override is StandardMaterial3D):
			continue
		var colour: Color = (mesh.material_override as StandardMaterial3D).albedo_color
		if colour == RouteSegment.ROAD or colour == GravelSegment.GRAVEL:
			mesh.material_override = road
			done.road += 1
			# A hidden box is only collision: what is drawn there (a bridge's deck) is not this surface.
			if mesh.visible:
				roadway.append(mesh)
				_tag_underfoot(mesh.get_parent(), surface)
		elif colour == RouteSegment.SHOULDER:
			mesh.material_override = verge
			done.verge += 1
			_tag_underfoot(mesh.get_parent(), VERGE)
		elif not marked and is_line(mesh) and mesh.visible:
			mesh.visible = false
			done.lines_hidden += 1
	if segment is MudSegment:
		_tag_underfoot(segment.get_node_or_null(^"Road"), &"dirt")
	_add_grip(segment, surface, roadway)
	return done


## True for a mesh painted as a lane line (LINE_COLOURS, and not a rail crossing's stop line).
static func is_line(mesh: MeshInstance3D) -> bool:
	var paint := mesh.material_override as StandardMaterial3D
	if paint == null or not LINE_COLOURS.has(paint.albedo_color):
		return false
	return not mesh.get_parent().is_in_group(RailCrossingSegment.STOP_LINE_GROUP)


## Tells whoever stands on `body` what it is (see UNDERFOOT).
static func _tag_underfoot(body: Node, surface: StringName) -> void:
	if body is StaticBody3D:
		body.set_meta(AUDIO_META, UNDERFOOT[surface][0])
		body.set_meta(ROUGHNESS_META, UNDERFOOT[surface][1])


## A GripArea over `roadway` when the piece's surface is loose. A GravelSegment and a MudSegment have their own.
static func _add_grip(segment: RouteSegment, surface: StringName, roadway: Array[MeshInstance3D]) -> void:
	if not GRIP.has(surface) or roadway.is_empty() or segment is GravelSegment or segment is MudSegment:
		return
	if segment.get_node_or_null(NodePath(GRIP_NODE)) != null:
		return
	var area := GripArea.new()
	area.name = GRIP_NODE
	area.slip = GRIP[surface]
	segment.add_child(area)
	var to_piece: Transform3D = segment.global_transform.affine_inverse()
	for mesh: MeshInstance3D in roadway:
		var size: Vector3 = (mesh.mesh as BoxMesh).size
		var top: Transform3D = mesh.global_transform.translated_local(Vector3.UP * size.y * 0.5)
		area.add_box(to_piece * top, Vector2(size.x, size.z))
