shader_type spatial;
// The far mountain ring (RouteSky): unshaded and fog-free like before -- at
// 280 m the level's fog would swallow it, and the sun's own shading only
// added noise -- but not one flat colour any more. Each peak's low-poly
// facets take a soft fixed light, the ridges catch a little more of it, and
// the foot melts into the sky's horizon colour (aerial haze), so the ring
// reads as distant mountains with depth. At night the flat version came out
// a near-black cut-out against the sky (playtest 2026-09-25).
// GL Compatibility friendly: no textures, no loops.
render_mode unshaded, fog_disabled, cull_back;

uniform vec3 body_color : source_color = vec3(0.2, 0.33, 0.35);
// The sky's horizon: what the foot fades into.
uniform vec3 haze_color : source_color = vec3(0.5, 0.61, 0.56);
// World heights of the ring's foot and its highest peaks.
uniform float foot_y = -6.0;
uniform float top_y = 74.0;
uniform float foot_haze : hint_range(0.0, 1.0) = 0.6;
uniform float ridge_lift : hint_range(0.0, 1.0) = 0.15;
uniform vec3 light_direction = vec3(0.45, 0.75, 0.35);
uniform float facet_contrast : hint_range(0.0, 1.0) = 0.14;

varying float height;
varying vec3 world_normal;

void vertex() {
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float h = clamp((height - foot_y) / max(top_y - foot_y, 0.001), 0.0, 1.0);
	float facing = dot(normalize(world_normal), normalize(light_direction));
	vec3 color = body_color * (1.0 + facet_contrast * facing) * (1.0 + ridge_lift * h);
	color = mix(color, haze_color, foot_haze * (1.0 - smoothstep(0.0, 0.55, h)));
	ALBEDO = color;
}
