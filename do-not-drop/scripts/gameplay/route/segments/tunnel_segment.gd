extends RouteSegment
class_name TunnelSegment
## A short tunnel (docs/tareas-nacho.md #58): walls, a roof under a grassy
## cover and concrete portals, dim inside (the roof shades it from the sun)
## with a few warm lights along the ceiling. Solid walls, so a sloppy line
## scrapes the truck along them.

const HALF_WIDTH: float = 4.7
const HEIGHT: float = 4.8
const PORTAL := Color("7d8784")
const LAMP := Color("ffd89a")


func _init() -> void:
	length = 44.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	var middle: float = -length * 0.5
	for side: float in [-1.0, 1.0]:
		_box("TunnelWall", Vector3(0.6, HEIGHT, length), Vector3(side * (HALF_WIDTH + 0.3), HEIGHT * 0.5, middle), CONCRETE, true)
		# A kerb strip so the foot of the wall reads at speed.
		_box("TunnelKerb", Vector3(0.35, 0.18, length), Vector3(side * (HALF_WIDTH - 0.17), 0.09, middle), WARNING)
	_box("TunnelRoof", Vector3(HALF_WIDTH * 2.0 + 1.2, 0.5, length), Vector3(0.0, HEIGHT + 0.25, middle), CONCRETE, true)
	# Earth heaped over the roof: from outside it reads as a hill with a hole.
	_box("TunnelCover", Vector3(HALF_WIDTH * 2.0 + 1.6, 1.4, length - 1.0), Vector3(0.0, HEIGHT + 1.2, middle), Color("4f7a3b"))
	for end_z: float in [0.0, -length]:
		_box("TunnelPortal", Vector3(HALF_WIDTH * 2.0 + 3.0, 1.6, 0.8), Vector3(0.0, HEIGHT + 0.8, end_z), PORTAL, true)
		for side: float in [-1.0, 1.0]:
			_box("TunnelPortalPier", Vector3(1.2, HEIGHT, 0.8), Vector3(side * (HALF_WIDTH + 0.9), HEIGHT * 0.5, end_z), PORTAL, true)
	# Warm lamps along the ceiling: an emissive strip each, a few real lights.
	var lamp_material := _material(LAMP).duplicate() as StandardMaterial3D
	lamp_material.emission_enabled = true
	lamp_material.emission = LAMP
	lamp_material.emission_energy_multiplier = 1.6
	for index: int in range(4):
		var z: float = -6.0 - float(index) * ((length - 12.0) / 3.0)
		var lamp: Node3D = _box("TunnelLamp", Vector3(0.9, 0.08, 0.3), Vector3(0.0, HEIGHT - 0.05, z), LAMP)
		for child: Node in lamp.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).material_override = lamp_material
		if index != 1:
			# Spot lights, not omni: the truck's headlights are spots, so their
			# shader variants are compiled from the first frame. The first omni
			# light the renderer met stalled a frame for ~0.1-0.6 s on entry.
			var light := SpotLight3D.new()
			light.name = "TunnelLight"
			light.light_color = LAMP
			light.light_energy = 2.2
			light.spot_range = 9.0
			light.spot_angle = 70.0
			light.shadow_enabled = false
			light.position = Vector3(0.0, HEIGHT - 0.3, z)
			light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			add_child(light)
