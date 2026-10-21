class_name GelCostumeSprings
extends "res://scripts/gameplay/player/gel/gel_hair_springs.gd"
## Reuses the native secondary-motion rig for tagged costume chains (S-311.73).
## Costume geometry owns the chain layout; this controller only binds and drives it.


func setup(costume: Node3D) -> bool:
	var built: bool = super.setup(costume)
	if built:
		skeleton().name = "GelCostumeSkeleton"
	return built
