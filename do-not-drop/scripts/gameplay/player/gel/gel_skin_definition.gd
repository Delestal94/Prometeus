class_name GelSkinDefinition
extends Resource
## One selectable gel skin: base colour (S-311.65) plus optional interior (S-311.66).

enum InteriorMode {
	NONE,
	LAYERS,
	VERTICAL_GRADIENT,
	FRUIT_BITS,
	GLITTER,
	BIG_BUBBLES,
}

@export var id: StringName = &""
@export var color: Color = Color.WHITE
## Beer-Lambert absorption coefficient used by the gel shader (0 = clear, 8 = dense).
@export_range(0.0, 8.0, 0.05) var absorption: float = 2.4
## Perceptual surface gloss (0 = matte, 1 = mirror-like).
@export_range(0.0, 1.0, 0.01) var shine: float = 0.9
@export var interior_mode: InteriorMode = InteriorMode.NONE
@export var interior_color: Color = Color.TRANSPARENT
@export_range(0.0, 1.0, 0.01) var interior_amount: float = 0.0
@export_range(1.0, 96.0, 0.5) var interior_scale: float = 8.0


func is_valid() -> bool:
	var finite_color := is_finite(color.r) and is_finite(color.g) \
		and is_finite(color.b) and is_finite(color.a)
	var finite_interior := is_finite(interior_color.r) and is_finite(interior_color.g) \
		and is_finite(interior_color.b) and is_finite(interior_color.a)
	var valid_mode := interior_mode >= InteriorMode.NONE and interior_mode <= InteriorMode.BIG_BUBBLES
	var valid_interior := valid_mode and (interior_mode == InteriorMode.NONE \
		or (interior_color.a > 0.0 and interior_amount > 0.0))
	return not id.is_empty() and finite_color \
		and finite_interior and valid_interior \
		and absorption >= 0.0 and absorption <= 8.0 \
		and shine >= 0.0 and shine <= 1.0 \
		and interior_scale >= 1.0 and interior_scale <= 96.0
