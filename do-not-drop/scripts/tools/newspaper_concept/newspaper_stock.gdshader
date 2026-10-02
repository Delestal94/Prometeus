shader_type spatial;
// Newsprint for the newspaper study. Lit like the rest of the set, so folds,
// droop and the lamp read on the sheet; part of the colour is emitted so the
// type keeps its contrast in a dim office instead of turning grey.
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D page_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D reverse_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float sheet_tint = 1.0;
uniform float self_light : hint_range(0.0, 1.0) = 0.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 printed = texture(page_texture, UV).rgb;
	vec2 grain_uv = UV * vec2(2048.0, 1448.0);
	float grain = hash(floor(grain_uv));
	float fibre = hash(vec2(floor(grain_uv.x * 0.25), floor(grain_uv.y * 2.0)));
	float blotch = hash(floor(UV * vec2(9.0, 6.0)));
	float centre_fold = exp(-abs(UV.x - 0.5) * 210.0);
	float cross_fold = exp(-abs(UV.y - 0.51) * 250.0);
	float edge = 1.0 - smoothstep(0.0, 0.02, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	// The other side's print shows through as a soft smudge, never as text.
	vec3 reverse_ink = textureLod(reverse_texture, vec2(1.0 - UV.x, UV.y), 4.5).rgb;
	float show_through = (1.0 - dot(reverse_ink, vec3(0.299, 0.587, 0.114))) * 0.012;
	float variation = (grain - 0.5) * 0.03 + (fibre - 0.5) * 0.012 + (blotch - 0.5) * 0.02;
	float shading = 1.0 - centre_fold * 0.06 - cross_fold * 0.02;
	// Grain and reverse print chiefly affect the stock, keeping type crisp.
	float stock_mask = smoothstep(0.18, 0.65, dot(printed, vec3(0.299, 0.587, 0.114)));
	// Edges of cheap stock yellow first.
	vec3 aged = mix(printed, printed * vec3(0.97, 0.93, 0.82), edge * stock_mask);
	vec3 colour = aged * shading * sheet_tint + vec3((variation - show_through) * stock_mask);
	ALBEDO = colour;
	ROUGHNESS = 1.0;
	EMISSION = colour * self_light;
}
