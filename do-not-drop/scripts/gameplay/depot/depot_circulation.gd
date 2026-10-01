class_name DepotCirculation
extends RefCounted
## How people and machines move through the depot, painted on its floor
## (N-319): green pedestrian walkways with white edges from the spawn to each
## place, the forklift's yellow lane down the left side, zebra crossings where
## the two meet, the truck bay's darker slab, the crew's gathering rectangle,
## the control island's pad, and the wear and stains that tell the floor is
## used. Everything is paint: flat boxes in the depot's DepotKit, stacked in
## layers PAINT_THICKNESS apart so none of them z-fight.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")

const PAINT_THICKNESS: float = 0.004
## Paint layers, bottom to top.
const LAYER_SLAB: int = 0
const LAYER_WALK: int = 1
const LAYER_LINE: int = 2
const LAYER_MARK: int = 3
const EDGE: float = 0.07
## The crew's rectangle: dashed outline, 10 cm wide, dash and gap lengths.
const GATHER_LINE: float = 0.1
const GATHER_DASH: float = 0.5
const GATHER_GAP: float = 0.3
## Zone arrows painted on the walkways: short (their tip stays clear of the white
## edge strips, 10 cm in from them on the 1 m walkway), opaque, in the floor's own finish.
const ARROW_LENGTH: float = 0.6
## How far over paint_arrow's base (7 mm over the slab) an arrow sits: its flat top at
## 14 mm, over the walkway's green (8 mm) and clear of the white edges' top (12 mm).
const ARROW_LIFT: float = 0.007
## Zebra bars: parallel to the traffic, this wide and this far apart.
const ZEBRA_BAR: float = 0.22
const ZEBRA_PITCH: float = 0.42

var _root: Node3D
var _green: StandardMaterial3D
var _white: StandardMaterial3D
var _yellow: StandardMaterial3D


func _init(root: Node3D) -> void:
	_root = root
	# Worn paint: the plaster's detail map breaks the colour up a little.
	_green = DepotKit.detailed(Layout.WALK_GREEN, "plaster", 1.5, 0.7)
	_white = DepotKit.detailed(Layout.MARKING, "stone", 0.8, 0.8)
	_yellow = DepotKit.flat(Layout.LANE_YELLOW, 0.7)


func build(kit: DepotKit) -> void:
	_build_bay(kit)
	_build_pads(kit)
	await kit.tick()
	_build_walkways(kit)
	await kit.tick()
	_build_forklift_lane(kit)
	_build_wear(kit)
	await kit.tick()
	_build_bollards(kit)


## The truck's bay: a darker sealed slab between the yellow edges, so the
## truck stands out from the floor instead of matching it.
func _build_bay(kit: DepotKit) -> void:
	_paint(kit, DepotKit.detailed(Color("485256"), "plaster", 2.0, 0.42), Rect2(-3.3, 1.5, 6.6, 11.9), LAYER_SLAB)
	for x: float in [-3.3, 3.3]:
		_paint(kit, _yellow, Rect2(x - 0.05, 1.5, 0.1, 13.0), LAYER_LINE)
	for x: float in [-1.9, 1.9]:
		_paint(kit, _white, Rect2(x - 0.06, 2.2, 0.12, 11.2), LAYER_LINE)
	_paint(kit, _white, Rect2(-1.96, 13.34, 3.92, 0.12), LAYER_LINE)
	# Hazard band inside the door.
	_paint(kit, DepotKit.stripes(Layout.YELLOW, Color("2b3136"), 0.25), Rect2(-Layout.DOOR_WIDTH * 0.5, 0.3,
			Layout.DOOR_WIDTH, 1.2), LAYER_MARK)


## The crew's gathering rectangle around the spawn row (a dashed yellow
## outline and a stencilled group of people, no fill) and the control island's
## pad, with its own edge lines.
func _build_pads(kit: DepotKit) -> void:
	_build_gathering(kit, Layout.GATHER)
	var island: Rect2 = Layout.ISLAND
	_paint(kit, DepotKit.detailed(Color("4f6467"), "plaster", 2.0, 0.45), island, LAYER_SLAB)
	for edge: Rect2 in [Rect2(island.position.x, island.position.y, island.size.x, 0.08),
			Rect2(island.position.x, island.end.y - 0.08, island.size.x, 0.08),
			Rect2(island.position.x, island.position.y, 0.08, island.size.y),
			Rect2(island.end.x - 0.08, island.position.y, 0.08, island.size.y)]:
		_paint(kit, _white, edge, LAYER_LINE)


## A dashed outline of `area` in warning yellow, and the stencil of three people
## standing together in the middle of it (heads are discs, bodies are rounded
## slabs: paint, like the rest).
func _build_gathering(kit: DepotKit, area: Rect2) -> void:
	for edge: int in range(4):
		var along_x: bool = edge < 2
		var start: Vector2 = area.position if edge % 2 == 0 else area.end
		var length: float = area.size.x if along_x else area.size.y
		# Whole dashes, spread so each side starts and ends on one.
		var pitch: float = GATHER_DASH + GATHER_GAP
		var count: int = maxi(int(round((length + GATHER_GAP) / pitch)), 1)
		var dash: float = (length - GATHER_GAP * (count - 1)) / count
		for index: int in range(count):
			var from: float = index * (dash + GATHER_GAP)
			if along_x:
				var z: float = start.y - (GATHER_LINE if edge == 1 else 0.0)
				_paint(kit, _yellow, Rect2(area.position.x + from, z, dash, GATHER_LINE), LAYER_MARK)
			else:
				var x: float = start.x - (GATHER_LINE if edge == 3 else 0.0)
				_paint(kit, _yellow, Rect2(x, area.position.y + from, GATHER_LINE, dash), LAYER_MARK)
	# The stencil: the middle person a little taller, the side ones a step back.
	var middle: Vector2 = area.get_center()
	for person: Array in [[-0.62, 0.0, 0.85], [0.0, 0.08, 1.0], [0.62, 0.0, 0.85]]:
		var scale: float = person[2]
		var foot := Vector3(middle.x + float(person[0]), Layout.FLOOR_TOP + (LAYER_MARK + 0.5) * PAINT_THICKNESS,
				middle.y + float(person[1]))
		_paint(kit, _yellow, Rect2(foot.x - 0.17 * scale, foot.z - 0.05 * scale, 0.34 * scale, 0.42 * scale),
				LAYER_MARK)
		kit.cylinder(0.11 * scale, PAINT_THICKNESS, Transform3D(Basis.IDENTITY, foot + Vector3(0.0, 0.0, -0.3 * scale)),
				_yellow, 14)


## The network of green walkways. The spine runs behind the truck's loading
## zone; a branch leads to each place.
func _build_walkways(kit: DepotKit) -> void:
	var spine: float = Layout.SPINE_Z
	var lane_x := Vector2(Layout.FORKLIFT_LANE_X - Layout.FORKLIFT_LANE_WIDTH * 0.5,
			Layout.FORKLIFT_LANE_X + Layout.FORKLIFT_LANE_WIDTH * 0.5)
	var aisle_x: float = -8.5
	var east_x: float = 8.5
	var half: float = Layout.WALK_WIDTH * 0.5
	var aisle_join := Vector2(aisle_x - half, aisle_x + half)
	var east_join := Vector2(east_x - half, east_x + half)
	var spine_join := Vector2(spine - half, spine + half)
	# West along the spine: through the aisle mouth and across the forklift lane.
	_walkway(kit, true, Vector2(-14.3, lane_x.x), spine, [])
	_walkway(kit, true, Vector2(lane_x.y, -3.5), spine, [aisle_join])
	# East along the spine, to the stair and the workshop's edge.
	_walkway(kit, true, Vector2(3.5, east_x + half), spine, [east_join])
	# Into the shelving aisle, and on to the back band.
	_walkway(kit, false, Vector2(spine + half, 24.6), aisle_x, [])
	# South to the supplies cage's window.
	_walkway(kit, false, Vector2(4.4, spine - half), aisle_x, [])
	# Along the back of the aisle, across the lane, to the packing table.
	_walkway(kit, true, Vector2(-14.3, lane_x.x), 25.2, [])
	_walkway(kit, true, Vector2(lane_x.y, 3.0), 25.2, [aisle_join])
	# Up the east side: from the workshop's gap to the office stair.
	_walkway(kit, false, Vector2(8.3, Layout.MEZZANINE.position.y - Layout.STAIR_RUN - 0.3), east_x, [spine_join])
	# From the gathering rectangle down to the spine.
	for x: float in [-1.5, 2.6]:
		_walkway(kit, false, Vector2(spine + half, Layout.GATHER.position.y), x, [])
	# Zebra crossings: over the truck's lane at both ends of the loading zone,
	# and over the forklift's lane where the walkways cross it.
	_zebra(kit, Vector2(1.95, 3.45), spine)
	_zebra(kit, Vector2(-3.45, -1.95), spine)
	_zebra(kit, lane_x, spine)
	_zebra(kit, lane_x, 25.2)
	# One small arrow per place, in its colour, aimed at it.
	for guide: Dictionary in Layout.FLOOR_GUIDES:
		var at: Vector3 = guide.arrow
		# Over the walkway's paint, short of its white edges.
		_arrows.append(DepotLabels.paint_arrow(kit, _root.tr(guide.caption), at,
				((guide.toward as Vector3) - at).normalized(), guide.colour, ARROW_LIFT, ARROW_LENGTH))


var _arrows: Array[Dictionary] = []


## The arrows painted by build(): {"caption", "at", "direction"}.
func arrows() -> Array[Dictionary]:
	return _arrows


## A green strip with white edges. `along` is its extent on the axis it runs
## along, `across` the coordinate of its centre on the other axis; the edges
## stay open over `gaps` (ranges on the running axis), where another walkway
## joins.
func _walkway(kit: DepotKit, along_x: bool, along: Vector2, across: float, gaps: Array[Vector2]) -> void:
	var width: float = Layout.WALK_WIDTH
	_paint(kit, _green, _strip(along_x, along, across, width), LAYER_WALK)
	for edge: float in [-1.0, 1.0]:
		var line_across: float = across + edge * (width * 0.5 - EDGE * 0.5)
		for piece: Vector2 in _without(along, gaps):
			_paint(kit, _white, _strip(along_x, piece, line_across, EDGE), LAYER_LINE)


## Zebra bars for someone walking along X across `x_range` at z = `at_z`.
func _zebra(kit: DepotKit, x_range: Vector2, at_z: float) -> void:
	var count: int = int(floorf((x_range.y - x_range.x - ZEBRA_BAR) / ZEBRA_PITCH)) + 1
	var start: float = (x_range.x + x_range.y) * 0.5 - (count - 1) * ZEBRA_PITCH * 0.5
	for index: int in range(count):
		var x: float = start + index * ZEBRA_PITCH
		_paint(kit, _white, Rect2(x - ZEBRA_BAR * 0.5, at_z - Layout.WALK_WIDTH * 0.5, ZEBRA_BAR, Layout.WALK_WIDTH),
				LAYER_MARK)


## The forklift's lane: yellow edges, hazard caps at both ends, its name.
func _build_forklift_lane(kit: DepotKit) -> void:
	var z: Vector2 = Layout.FORKLIFT_LANE_Z
	var x0: float = Layout.FORKLIFT_LANE_X - Layout.FORKLIFT_LANE_WIDTH * 0.5
	var x1: float = Layout.FORKLIFT_LANE_X + Layout.FORKLIFT_LANE_WIDTH * 0.5
	for x: float in [x0, x1]:
		_paint(kit, _yellow, Rect2(x - 0.05, z.x, 0.1, z.y - z.x), LAYER_LINE)
	var hazard := DepotKit.stripes(Layout.YELLOW, Color("2b3136"), 0.2)
	for end: float in [z.x, z.y - 0.5]:
		_paint(kit, hazard, Rect2(x0, end, x1 - x0, 0.5), LAYER_LINE)
	DepotLabels.floor_text(_root, _root.tr("WORLD_DEPOT_FLOOR_FORKLIFT"), Vector3(Layout.FORKLIFT_LANE_X, 0.0, 19.4),
			-PI * 0.5, 44, Color(Layout.YELLOW, 0.85))


## Tyre tracks, worn lanes and a few oil stains: soft dark patches a few
## millimetres over the concrete (there is no room for them on the paint).
func _build_wear(kit: DepotKit) -> void:
	var dark := DepotKit.stain(Color(0.03, 0.04, 0.05, 0.16))
	var oil := DepotKit.stain(Color(0.02, 0.02, 0.02, 0.32))
	var lane := Vector2(Layout.FORKLIFT_LANE_Z.x + 0.9, Layout.FORKLIFT_LANE_Z.y - 0.9)
	# The forklift's own track, worn by its wheels.
	kit.floor_quad(Vector2(1.3, lane.y - lane.x), Vector3(Layout.FORKLIFT_LANE_X, Layout.FLOOR_TOP + 0.0032,
			(lane.x + lane.y) * 0.5), dark)
	# The truck's tyre tracks, on the bay's slab, from the door to the ramp.
	for x: float in [-1.05, 1.05]:
		kit.floor_quad(Vector2(0.6, 11.0), Vector3(x, Layout.FLOOR_TOP + 0.0065, 7.6), DepotKit.stain(Color(0.0, 0.0,
				0.0, 0.2)))
	# Scuffs where feet and trolleys turn: the spawn row, the cage's window, the belt's end.
	for scuff: Array in [[Vector3(0.6, 0.0, 17.4), Vector2(5.2, 2.6)], [Vector3(-8.3, 0.0, 5.4), Vector2(2.6, 3.2)],
			[Vector3(4.6, 0.0, 29.3), Vector2(3.0, 2.0)], [Vector3(-8.5, 0.0, 19.5), Vector2(2.2, 8.0)],
			[Vector3(2.4, 0.0, 25.2), Vector2(5.0, 1.4)]]:
		var at: Vector3 = scuff[0]
		kit.floor_quad(scuff[1], Vector3(at.x, Layout.FLOOR_TOP + 0.0032, at.z), dark)
	# Oil, where the machines stand still.
	for blot: Array in [[Vector3(-12.3, 0.0, 11.0), 0.9], [Vector3(-11.5, 0.0, 21.5), 0.6], [Vector3(6.2, 0.0, 6.4),
			0.7],
			[Vector3(0.9, 0.0, 10.4), 0.5], [Vector3(-3.1, 0.0, 27.0), 0.5], [Vector3(7.2, 0.0, 12.3), 0.45]]:
		var blot_at: Vector3 = blot[0]
		var radius: float = blot[1]
		kit.floor_quad(Vector2(radius * 1.6, radius), Vector3(blot_at.x, Layout.FLOOR_TOP + 0.0034, blot_at.z), oil,
				blot_at.x * 1.7)


## Yellow and black bollards at the bay's corners (the kit's model, solid as before):
## the truck's bay is not a place to cut across with a pallet jack. Two wheel stops
## ahead of the truck's front wheels and a pair of chocks left by the bollards.
func _build_bollards(kit: DepotKit) -> void:
	var bollard: String = DepotKit.depot_model("sm_env_depot_bollard")
	for at: Vector2 in [Vector2(-3.85, 1.9), Vector2(3.85, 1.9), Vector2(-3.85, 12.9), Vector2(3.85, 12.9)]:
		kit.model(bollard, Transform3D(Basis.IDENTITY, Vector3(at.x, Layout.FLOOR_TOP, at.y)))
		kit.collider(Vector3(0.24, 1.0, 0.24), Transform3D(Basis.IDENTITY, Vector3(at.x, Layout.FLOOR_TOP + 0.5, at.y)))
	var stop: String = DepotKit.depot_model("sm_env_depot_wheel_stop")
	for x: float in [-1.05, 1.05]:
		kit.model(stop, Transform3D(Basis.IDENTITY, Vector3(x, Layout.FLOOR_TOP, 4.55)))
	var chock: String = DepotKit.depot_model("sm_env_depot_wheel_chock")
	kit.model(chock, Transform3D(Basis(Vector3.UP, 0.35), Vector3(-3.45, Layout.FLOOR_TOP, 12.2)))
	kit.model(chock, Transform3D(Basis(Vector3.UP, -0.25), Vector3(3.5, Layout.FLOOR_TOP, 2.5)))


# --- Helpers ---------------------------------------------------------------------


## A flat box of paint on `layer` over the concrete.
func _paint(kit: DepotKit, material: Material, area: Rect2, layer: int) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(area.size.x, PAINT_THICKNESS, area.size.y)
	var centre := area.get_center()
	kit.add_mesh(mesh, Transform3D(Basis.IDENTITY,
			Vector3(centre.x, Layout.FLOOR_TOP + (layer + 0.5) * PAINT_THICKNESS, centre.y)), material, false)


## The rectangle of a strip `width` wide running along X (or Z) over `along`,
## centred at `across` on the other axis.
func _strip(along_x: bool, along: Vector2, across: float, width: float) -> Rect2:
	if along_x:
		return Rect2(along.x, across - width * 0.5, along.y - along.x, width)
	return Rect2(across - width * 0.5, along.x, width, along.y - along.x)


## `range` minus the `gaps` inside it, as the pieces left.
func _without(range: Vector2, gaps: Array[Vector2]) -> Array[Vector2]:
	var pieces: Array[Vector2] = [range]
	for gap: Vector2 in gaps:
		var next: Array[Vector2] = []
		for piece: Vector2 in pieces:
			if gap.y <= piece.x or gap.x >= piece.y:
				next.append(piece)
				continue
			if gap.x > piece.x:
				next.append(Vector2(piece.x, gap.x))
			if gap.y < piece.y:
				next.append(Vector2(gap.y, piece.y))
		pieces = next
	return pieces
