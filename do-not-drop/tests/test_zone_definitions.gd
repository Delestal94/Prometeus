extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_zone_definitions.gd
##
## The zone data of the continuous map (expansion D-0205, zone_definition.gd):
## - the nine files in data/zones/ load as ZoneDefinition, with the file name
##   as id and a WORLD_ZONE_<ID> display key;
## - the bounds do not overlap (touching edges are fine) and sit inside the
##   6x6 km map (-3072..3072 on X and Z);
## - gate ids start with "gate_", are unique across zones and, once
##   data/gates/ exists (D-0306), each one has its <id>.tres there;
## - only parque_industrial and centro are open at the start;
## - the three F1 zones carry full data: vehicles, WorldMood weather
##   profiles, shipping fee and houses per trip.

const ZONES_DIR := "res://data/zones"
const GATES_DIR := "res://data/gates"
const MAP_LIMIT: float = 3072.0
const ZONE_IDS: Array[String] = [
	"campo",
	"centro",
	"islas",
	"montana",
	"nieve",
	"parque_industrial",
	"puerto",
	"suburbio",
	"volcan",
]
const OPEN_AT_START: Array[String] = ["centro", "parque_industrial"]
const WEATHERS: Array[StringName] = [&"soleado", &"nublado", &"lluvia", &"niebla"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array[String] = _list_ids(ZONES_DIR)
	_expect(ids == ZONE_IDS, "data/zones/ holds the nine zones (got %s)" % [ids])

	var zones: Dictionary = {}
	var gate_owner: Dictionary = {}
	for file_id: String in ids:
		var zone: ZoneDefinition = load("%s/%s.tres" % [ZONES_DIR, file_id]) as ZoneDefinition
		_expect(zone != null, "%s loads as ZoneDefinition" % file_id)
		if zone == null:
			continue
		zones[file_id] = zone
		_check_zone(file_id, zone, gate_owner)

	_check_overlaps(zones)
	_check_open_at_start(zones)
	_check_f1_zones(zones)
	_check_helpers(zones)

	if _failures == 0:
		print("PASS: zone definitions (%d zones)" % zones.size())
	quit(_failures)


func _check_zone(file_id: String, zone: ZoneDefinition, gate_owner: Dictionary) -> void:
	_expect(String(zone.id) == file_id, "%s: id equals the file name (got %s)" % [file_id, zone.id])
	_expect(
		zone.display_key == "WORLD_ZONE_" + file_id.to_upper(),
		"%s: display_key is WORLD_ZONE_<ID> (got %s)" % [file_id, zone.display_key]
	)
	var b: Rect2 = zone.bounds
	_expect(b.size.x > 0.0 and b.size.y > 0.0, "%s: bounds has an area (got %s)" % [file_id, b])
	_expect(
		b.position.x >= -MAP_LIMIT and b.end.x <= MAP_LIMIT,
		"%s: bounds fit the map on X (got %s)" % [file_id, b]
	)
	_expect(
		b.position.y >= -MAP_LIMIT and b.end.y <= MAP_LIMIT,
		"%s: bounds fit the map on Z (got %s)" % [file_id, b]
	)
	for gate: StringName in zone.gates:
		_expect(
			String(gate).begins_with("gate_"), "%s: gate %s starts with gate_" % [file_id, gate]
		)
		_expect(
			not gate_owner.has(gate),
			"%s: gate %s is unique (also in %s)" % [file_id, gate, gate_owner.get(gate, "")]
		)
		gate_owner[gate] = file_id
		# D-0306 creates data/gates/; until then the folder is missing and the
		# check is skipped.
		if DirAccess.dir_exists_absolute(GATES_DIR):
			var gate_path: String = "%s/%s.tres" % [GATES_DIR, gate]
			_expect(ResourceLoader.exists(gate_path), "%s: %s exists" % [file_id, gate_path])


func _check_overlaps(zones: Dictionary) -> void:
	var ids: Array = zones.keys()
	ids.sort()
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var a: ZoneDefinition = zones[ids[i]]
			var b: ZoneDefinition = zones[ids[j]]
			_expect(
				not a.bounds.intersects(b.bounds, false),
				"%s and %s do not overlap (%s vs %s)" % [ids[i], ids[j], a.bounds, b.bounds]
			)


func _check_open_at_start(zones: Dictionary) -> void:
	var open: Array[String] = []
	for file_id: String in zones:
		if (zones[file_id] as ZoneDefinition).is_open_at_start():
			open.append(file_id)
	open.sort()
	_expect(open == OPEN_AT_START, "zones open at start are the depot and centro (got %s)" % [open])


func _check_f1_zones(zones: Dictionary) -> void:
	for file_id: String in ["parque_industrial", "centro", "campo"]:
		var zone: ZoneDefinition = zones.get(file_id)
		if zone == null:
			continue
		_expect(not zone.vehicles.is_empty(), "%s: vehicles is not empty" % file_id)
		_expect(not zone.mood_profiles.is_empty(), "%s: mood_profiles is not empty" % file_id)
		for profile: StringName in zone.mood_profiles:
			_expect(
				WEATHERS.has(profile),
				"%s: mood profile %s is a WorldMood weather" % [file_id, profile]
			)
	_expect_fee_and_houses(zones, "centro", 40, Vector2i(4, 6))
	_expect_fee_and_houses(zones, "campo", 60, Vector2i(3, 5))
	_expect_fee_and_houses(zones, "parque_industrial", 0, Vector2i(0, 0))


func _expect_fee_and_houses(zones: Dictionary, id: String, fee: int, houses: Vector2i) -> void:
	var zone: ZoneDefinition = zones.get(id)
	if zone == null:
		return
	_expect(
		zone.shipping_fee == fee, "%s: shipping_fee is %d (got %d)" % [id, fee, zone.shipping_fee]
	)
	_expect(
		zone.houses_per_trip == houses,
		"%s: houses_per_trip is %s (got %s)" % [id, houses, zone.houses_per_trip]
	)


func _check_helpers(zones: Dictionary) -> void:
	var parque: ZoneDefinition = zones.get("parque_industrial")
	if parque == null:
		return
	_expect(parque.contains_xz(Vector3.ZERO), "the depot zone contains the origin")
	_expect(
		not parque.contains_xz(Vector3(1000.0, 5.0, 0.0)),
		"the depot zone does not contain a far point"
	)


## The ids of the .tres files in a folder, sorted. Exported builds list them
## as "<name>.tres.remap", so that suffix is stripped.
func _list_ids(dir_path: String) -> Array[String]:
	var ids: Array[String] = []
	for file_name: String in DirAccess.get_files_at(dir_path):
		var clean: String = file_name.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			ids.append(clean.get_basename())
	ids.sort()
	return ids


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
