class_name GelSkinDefinition
extends Resource
## One selectable base gel colour (S-311.65).
## Interior layers and animation are separate skin features added in later tasks.

@export var id: StringName = &""
@export var color: Color = Color.WHITE
## Beer-Lambert absorption coefficient used by the gel shader (0 = clear, 8 = dense).
@export_range(0.0, 8.0, 0.05) var absorption: float = 2.4
## Perceptual surface gloss (0 = matte, 1 = mirror-like).
@export_range(0.0, 1.0, 0.01) var shine: float = 0.9


func is_valid() -> bool:
	var finite_color := is_finite(color.r) and is_finite(color.g) \
		and is_finite(color.b) and is_finite(color.a)
	return not id.is_empty() and finite_color \
		and absorption >= 0.0 and absorption <= 8.0 \
		and shine >= 0.0 and shine <= 1.0
