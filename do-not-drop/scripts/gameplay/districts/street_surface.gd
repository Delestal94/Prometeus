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
##   hidden. By colour, not by name: a piece's second line of the same name is renamed by Godot.
## Only what is drawn changes: the boxes, their collision and their size stay (the roadway is still the
## 12 m box Centro's sidewalks are laid against, CentroDecor.ROADWAY_HALF_WIDTH). One ShaderMaterial per
## surface for the whole map, shared by every piece (material()).

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
		elif colour == RouteSegment.SHOULDER:
			mesh.material_override = verge
			done.verge += 1
		elif not marked and LINE_COLOURS.has(colour) and mesh.visible:
			mesh.visible = false
			done.lines_hidden += 1
	return done


## True for a mesh painted as a lane line (LINE_COLOURS).
static func is_line(mesh: MeshInstance3D) -> bool:
	var paint := mesh.material_override as StandardMaterial3D
	return paint != null and LINE_COLOURS.has(paint.albedo_color)
