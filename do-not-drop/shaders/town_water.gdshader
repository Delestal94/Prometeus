shader_type spatial;
render_mode diffuse_burley, cull_disabled;

varying vec2 water_position;

void vertex() {
	water_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = water_position;
	float waves = sin(p.x * 0.7 + p.y * 0.4 + TIME * 0.9);
	float ripples = sin(p.y * 1.9 - p.x * 0.6 - TIME * 1.2);
	ALBEDO = vec3(0.16, 0.38, 0.48) + (waves + ripples) * 0.016;
	ROUGHNESS = 0.28 + waves * 0.025;
	SPECULAR = 0.65;
}
