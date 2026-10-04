extends SceneTree
## Run (needs a GPU, not --headless):
##   Godot --path do-not-drop --script res://tests/render_world_gates.gd
## Review shots of the map gates (expansion D-0306, world_gate.gd): one gate of
## each kind built by WorldGate itself, closed and then open, seen from the side
## the vehicle arrives from (+Z), with a 1.8 m post for scale. Saved to
## user://world_gate_<id>_{closed,open}.png.

const GATE_DIR: String = "res://data/gates/"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## Gate id -> [camera position, look-at point].
const SHOTS := {
	"gate_suburbio": [Vector3(4.0, 3.2, 12.0), Vector3(1.0, 1.4, 0.0)],
	"gate_campo_obra": [Vector3(2.0, 3.0, 11.0), Vector3(0.0, 1.0, 0.0)],
	"gate_nieve_equipo": [Vector3(1.0, 3.6, 14.0), Vector3(0.5, 1.6, 0.0)],
	"gate_islas_agua": [Vector3(1.2, 2.0, 4.2), Vector3(0.0, 1.6, 0.0)],
	"gate_montana_altura": [Vector3(1.2, 2.0, 4.2), Vector3(0.0, 1.8, 0.0)],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_build_stage(world)
	var camera := Camera3D.new()
	camera.fov = 55.0
	world.add_child(camera)
	for id: String in SHOTS:
		var state: Object = (load(STATE_SCRIPT) as GDScript).new()
		state.call("new_company", "Render")
		var gate := WorldGate.new()
		gate.setup(load(GATE_DIR + id + ".tres") as GateRequirement, state)
		gate.position = Vector3.ZERO
		world.add_child(gate)
		camera.position = SHOTS[id][0]
		camera.look_at(SHOTS[id][1])
		camera.make_current()
		await _save("%s_closed" % id)
		state.call("open_gate", StringName(id))
		gate.refresh()
		await _save("%s_open" % id)
		gate.free()
	quit(0)


func _build_stage(world: Node3D) -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.95)
	env.ambient_light_energy = 0.8
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	world.add_child(light)
	world.add_child(_box(Vector3(40.0, 0.02, 40.0), Vector3(0.0, -0.01, 0.0), Color(0.47, 0.6, 0.36)))
	world.add_child(_box(Vector3(8.0, 0.02, 40.0), Vector3(0.0, 0.0, 0.0), Color(0.3, 0.3, 0.32)))
	world.add_child(_box(Vector3(0.15, 1.8, 0.15), Vector3(-2.5, 0.9, 3.0), Color(0.9, 0.3, 0.2)))


func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = at
	return mesh


func _save(shot: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://world_gate_%s.png" % shot
	root.get_viewport().get_texture().get_image().save_png(path)
	print("RENDER: ", ProjectSettings.globalize_path(path))
