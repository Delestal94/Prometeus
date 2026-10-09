shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// S-311.27: the first GL Compatibility pass for the gelatin body. The view
// angle is the only input: front-facing fragments stay clear while grazing
// angles gain colour and opacity, so the silhouette reads as denser gel.
// Refraction, thickness absorption, back-light, bubbles and transparency
// ordering belong to the following material blocks and stay out of this pass.

group_uniforms gel;
uniform vec4 gel_color : source_color = vec4(0.78, 0.82, 0.92, 1.0);
uniform float center_opacity : hint_range(0.0, 1.0) = 0.24;
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.78;
uniform float edge_density : hint_range(0.0, 1.0) = 0.38;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.4;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.16;
uniform float specular : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	float density = fresnel * edge_density;
	ALBEDO = mix(gel_color.rgb, vec3(1.0), density * 0.48);
	ROUGHNESS = roughness;
	SPECULAR = specular;
	ALPHA = gel_color.a * mix(center_opacity, edge_opacity, fresnel);
}
