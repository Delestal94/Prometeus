extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_core_tradeoff.gd
## S-311.14 closes the internal-core experiment against the shipping thickness path.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const GEL_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")
const CORE_REPORT: String = "res://../art/gel_character/review_bloque_b/core_experiment_report.json"
const DECISION_REPORT: String = (
	"res://../art/gel_character/review_bloque_b/s311_14_core_tradeoff_final.json"
)
const BLOCK_E_REPORT: String = (
	"res://../art/gel_character/review_bloque_e/round_149/report.json"
)
const BLOCK_E_VISUAL: String = (
	"res://../art/gel_character/review_bloque_e/round_149/visual_review.json"
)
const PERFORMANCE_REPORT: String = (
	"res://../art/gel_character/review_bloque_d/s311_37_performance.md"
)
const CORE_ASSET: String = "res://../art/gel_character/review_bloque_b/core_experiment.glb"
const LOD0_BUDGET: int = 6000
const RUNTIME_LOD0_BUDGET: int = 20_000

var _failures: int = 0


func _initialize() -> void:
	_check_internal_core_trial()
	_check_shipping_solution()
	_check_block_e()
	_check_final_decision()
	if _failures == 0:
		print("PASS: thickness map beats the internal core and passes S-311.14")
	quit(_failures)


func _check_internal_core_trial() -> void:
	var report: Dictionary = _json(CORE_REPORT)
	_expect(not report.is_empty(), "the internal-core experiment report exists")
	_expect(FileAccess.file_exists(CORE_ASSET), "the internal-core experiment asset exists")
	_expect(bool(report.get(&"same_topology_morphs_weights", false)),
		"the core trial retained the outer body's topology, morphs and weights")
	_expect(int(report.get(&"outer_triangles", 0)) == 4704,
		"the core experiment measured the 4704-triangle outer body")
	_expect(int(report.get(&"core_triangles", 0)) == 4704,
		"the same-topology core adds another 4704 triangles")
	_expect(int(report.get(&"combined_triangles", 0)) == 9408,
		"the core experiment totals 9408 body triangles")
	_expect(bool(report.get(&"combined_exceeds_lod0_6000", false)),
		"the core candidate fails the hard 6000-triangle LOD0 budget")
	_expect(int(report.get(&"estimated_body_drawcalls", 0)) == 2,
		"the core candidate needs a second body draw")


func _check_shipping_solution() -> void:
	var body := GEL_SCENE.instantiate() as Node3D
	root.add_child(body)
	var meshes: Array[Node] = body.find_children("*", "MeshInstance3D", true, false)
	_expect(meshes.size() == 1, "the shipping body keeps one mesh instead of a core draw")
	var mesh_instance := meshes[0] as MeshInstance3D if not meshes.is_empty() else null
	var mesh: Mesh = mesh_instance.mesh if mesh_instance != null else null
	_expect(mesh != null and _triangle_count(mesh) == 18_816,
		"the imported shipping LOD0 keeps its certified runtime triangle count")
	_expect(mesh != null and _triangle_count(mesh) <= RUNTIME_LOD0_BUDGET,
		"the imported shipping LOD0 remains within its runtime triangle budget")
	_expect(mesh != null and mesh.get_blend_shape_count() == 11,
		"the shipping LOD0 retains all eleven morphs")
	var thickness := GEL_MATERIAL.get_shader_parameter(&"thickness_map") as Texture2D
	_expect(thickness != null and thickness.get_size() == Vector2(1024.0, 1024.0),
		"the selected solution uses the baked 1024x1024 thickness map")
	_expect(GEL_MATERIAL.next_pass == null,
		"thickness absorption stays in the existing material pass")
	var shader_code: String = GEL_MATERIAL.shader.code
	_expect(
		"texture(thickness_map, UV).r" in shader_code
		and "thickness_absorption * absorption_opacity" in shader_code,
		"the selected shader converts baked thickness into torso density"
	)
	body.free()


func _check_block_e() -> void:
	var report: Dictionary = _json(BLOCK_E_REPORT)
	var approval: Dictionary = report.get(&"approval", {})
	_expect(bool(approval.get(&"passed", false)),
		"the thickness-map render passes the complete Block E gate")
	var automatic: Dictionary = approval.get(&"automatic", {})
	_expect(float(automatic.get(&"silhouette", {}).get(&"value", 0.0)) >= 0.92,
		"the selected render passes the silhouette threshold")
	var zones: Dictionary = automatic.get(&"color_zones", {})
	_expect(float(zones.get(&"torso", {}).get(&"value", 99.0)) <= 8.0,
		"the selected render passes the torso color threshold")
	var visual: Dictionary = _json(BLOCK_E_VISUAL)
	var denser_torso_passed: bool = false
	for criterion: Dictionary in visual.get(&"criteria", []):
		if criterion.get(&"id") == "denser_torso":
			denser_torso_passed = criterion.get(&"result") == "yes"
	_expect(denser_torso_passed,
		"visual criterion 11 confirms a denser torso than the extremities")
	var performance: String = FileAccess.get_file_as_string(PERFORMANCE_REPORT)
	_expect("0,135 ms" in performance and "−0,011 ms" in performance,
		"the selected one-pass body retains the measured four-character GPU result")
	_expect("Resultado: **PASA**" in performance,
		"the selected solution passes the four-character performance budget")


func _check_final_decision() -> void:
	var decision: Dictionary = _json(DECISION_REPORT)
	_expect(decision.get(&"task") == "S-311.14", "the final decision names S-311.14")
	_expect(decision.get(&"decision") == "thickness_map",
		"the cheaper passing thickness-map solution is selected")
	_expect(bool(decision.get(&"decision_complete", false)),
		"the trade-off is explicitly closed after Blocks D and E")
	var core: Dictionary = decision.get(&"internal_core_trial", {})
	var thickness: Dictionary = decision.get(&"thickness_map_solution", {})
	_expect(not bool(core.get(&"selected", true)) and bool(thickness.get(&"selected", false)),
		"the final report rejects the core and keeps the thickness map")
	_expect(
		int(core.get(&"combined_triangles", 0)) > int(thickness.get(&"source_triangles", 0))
		and int(core.get(&"body_draw_calls", 0)) > int(thickness.get(&"body_draw_calls", 0)),
		"the selected solution is cheaper in geometry and body draws"
	)
	_expect(int(thickness.get(&"source_triangles", LOD0_BUDGET + 1)) <= LOD0_BUDGET,
		"the final report preserves the source LOD0 budget")
	_expect(
		int(thickness.get(&"runtime_triangles", RUNTIME_LOD0_BUDGET + 1))
		<= RUNTIME_LOD0_BUDGET,
		"the final report preserves the imported runtime LOD0 budget"
	)


func _triangle_count(mesh: Mesh) -> int:
	var total: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		total += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	return total


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failures += 1
