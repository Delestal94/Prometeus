class_name GelProportionRandomButton
extends Button
## Reusable "random" action for the proportion editor added in S-311.22.

signal proportions_randomized(proportions: GelBodyProportions)

const Presets := preload("res://scripts/gameplay/player/gel/gel_proportion_presets.gd")

@export var proportions: GelBodyProportions

var _rng := RandomNumberGenerator.new()
var _has_fixed_seed: bool = false


func _ready() -> void:
	text = tr("UI_GEL_PROPORTION_RANDOM")
	if not _has_fixed_seed:
		_rng.randomize()
	pressed.connect(randomize_proportions)


func set_random_seed(value: int) -> void:
	_has_fixed_seed = true
	_rng.seed = value


func randomize_proportions() -> void:
	if proportions == null:
		return
	Presets.randomize_safe(proportions, _rng)
	proportions_randomized.emit(proportions)
