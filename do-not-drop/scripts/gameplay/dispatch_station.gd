class_name DispatchStation
extends DepotStation
## The dispatch board's station in the company's shed (expansion D-0310.b, "Modo Empresa"): the
## DepotStation `dispatch` that CompanyShed puts on every dispatch zone it draws.
##
## Using it opens the dispatch board (DispatchBoardPanel) on the screen of whoever used it, through
## DepotStation's own path: interact() runs on the host, which bounces to that player's peer, where
## EventBus.depot_station_opened(&"dispatch") fires for the world adapter (CompanyDispatch) to show the
## board with the real data. Nothing is decided here.
##
## A DepotStation hides its prompt once a delivery run is on or has results (the depot is behind
## you); the company's world has no run, but a menu session that played one before still holds its
## results, so _run_started() is false here.
##
## Grey-box stand-in (subtask for modelador-blender, docs/expansion-distritos/arte-pendiente): a grey board
## with the zone's name on it, at the back of the zone. It has no collider: the zone is painted on the
## floor and does not block walking (blocks_walking = false), so the board must not either.

const ID: StringName = &"dispatch"
const PROMPT_KEY: String = "WORLD_SHED_USE_DISPATCH"
const SIGN_KEY: String = "WORLD_SHED_ZONE_DISPATCH"
## Reach of the point, in the middle of the zone (a 3 x 2 cell patch).
const REACH_RADIUS: float = 1.1
## The station's own height over the floor, and the board's.
const STATION_HEIGHT: float = 1.0
const BOARD_SIZE: Vector3 = Vector3(1.2, 0.7, 0.06)
const BOARD_HEIGHT: float = 1.3
const BOARD_COLOR: Color = Color(0.46, 0.47, 0.5)


## The station of the dispatch piece `uid`, in the piece's own frame (the shed puts it under the same
## transform as the piece): in the middle of the zone, one metre up, with its board on the far edge
## of a zone `depth_m` metres deep. Named by the piece, so its RPC path is the same on every peer.
static func make(uid: StringName, depth_m: float) -> DispatchStation:
	var station := DispatchStation.new()
	station.name = "Dispatch_%s" % uid
	station.station_id = ID
	station.position = Vector3(0.0, STATION_HEIGHT, 0.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = REACH_RADIUS
	shape.shape = sphere
	station.add_child(shape)
	var board := MeshInstance3D.new()
	board.name = "Board"
	var mesh := BoxMesh.new()
	mesh.size = BOARD_SIZE
	mesh.material = DepotKit.flat(BOARD_COLOR)
	board.mesh = mesh
	board.position = Vector3(0.0, BOARD_HEIGHT - STATION_HEIGHT, -depth_m * 0.5 + BOARD_SIZE.z)
	station.add_child(board)
	var title := Label3D.new()
	title.name = "Sign"
	title.text = TranslationServer.translate(SIGN_KEY)
	title.font_size = 28
	title.pixel_size = 0.004
	title.outline_size = 8
	title.position = Vector3(0.0, 0.0, BOARD_SIZE.z * 0.5 + 0.01)
	board.add_child(title)
	station.marker = title
	return station


func get_prompt() -> String:
	return tr(PROMPT_KEY)


## The company's world has no run to be behind.
func _run_started() -> bool:
	return false
