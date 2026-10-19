class_name GelSkinDefinition
extends Resource
## One selectable gel skin: base colour, optional interior and optional animation.

enum InteriorMode {
	NONE,
	LAYERS,
	VERTICAL_GRADIENT,
	FRUIT_BITS,
	GLITTER,
	BIG_BUBBLES,
}

enum AnimationMode {
	NONE,
	CYCLING_RAINBOW,
	NIGHT_NEON,
	SLOW_LAVA,
	HOLOGRAPHIC,
}

@export var id: StringName = &""
@export var color: Color = Color.WHITE
## Beer-Lambert absorption coefficient used by the gel shader (0 = clear, 8 = dense).
@export_range(0.0, 8.0, 0.05) var absorption: float = 2.4
## Perceptual surface gloss (0 = matte, 1 = mirror-like).
@export_range(0.0, 1.0, 0.01) var shine: float = 0.9
@export var interior_mode: InteriorMode = InteriorMode.NONE
@export var animation_mode: AnimationMode = AnimationMode.NONE
@export var interior_color: Color = Color.TRANSPARENT
## Strength for either the interior feature or animated effect.
@export_range(0.0, 1.0, 0.01) var interior_amount: float = 0.0
## Object-space scale for interiors; spatial frequency for animated effects.
@export_range(1.0, 96.0, 0.5) var interior_scale: float = 8.0


func is_valid() -> bool:
	var finite_color := is_finite(color.r) and is_finite(color.g) \
		and is_finite(color.b) and is_finite(color.a)
	var finite_interior := is_finite(interior_color.r) and is_finite(interior_color.g) \
		and is_finite(interior_color.b) and is_finite(interior_color.a)
	var valid_mode := interior_mode >= InteriorMode.NONE and interior_mode <= InteriorMode.BIG_BUBBLES
	var valid_animation := animation_mode >= AnimationMode.NONE \
		and animation_mode <= AnimationMode.HOLOGRAPHIC
	var one_effect := interior_mode == InteriorMode.NONE or animation_mode == AnimationMode.NONE
	var has_effect := interior_mode != InteriorMode.NONE or animation_mode != AnimationMode.NONE
	var valid_effect := not has_effect or (interior_color.a > 0.0 and interior_amount > 0.0)
	return not id.is_empty() and finite_color \
		and finite_interior and valid_mode and valid_animation and one_effect and valid_effect \
		and absorption >= 0.0 and absorption <= 8.0 \
		and shine >= 0.0 and shine <= 1.0 \
		and interior_scale >= 1.0 and interior_scale <= 96.0
