extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var van_scene := load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene
	assert(van_scene != null, "La escena del vehículo debe cargar")
	var van := van_scene.instantiate() as VehicleBody3D
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(van)
	await process_frame
	await process_frame
	var adapter := van.get_node_or_null("ReferenceTruck")
	var model := van.get_node_or_null("BodyVisuals/ReferenceTruckModel")
	assert(adapter != null, "El adaptador del camión debe existir")
	assert(model != null, "El modelo de referencia debe instalarse")
	assert(van.get_node("CargoBay/LeftShelfPackageMount").position.y > 0.6, "El anaquel debe tener un punto de carga accesible")
	assert(van.get_node("CabinInterior/DriverEyePoint").position.y > 1.4, "La cámara del conductor debe quedar dentro de la cabina")
	assert(van.get_node("RearDoorControl") != null, "Debe existir control para las puertas traseras")
	assert(van.get_node("RearClosedDoorCollision").get_child(0).disabled, "Con puertas abiertas se debe poder caminar a la carga")
	van.set_rear_cargo_open(false)
	assert(not van.get_node("RearClosedDoorCollision").get_child(0).disabled, "Las puertas cerradas bloquean el acceso")
	van.set_rear_cargo_open(true)
	var transparent_count := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if "window" in mesh.name.to_lower() or "glass" in mesh.name.to_lower():
			var material := mesh.material_override as StandardMaterial3D
			if material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				transparent_count += 1
	assert(transparent_count >= 4, "Parabrisas, laterales y ventana de comunicación deben ser transparentes")
	print("PASS: reference truck installs, opens rear access, keeps cargo mounts and transparent windows.")
	quit(0)
