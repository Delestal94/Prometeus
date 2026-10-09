shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// S-311.27-28: GL Compatibility gelatin with a clear centre, a denser Fresnel
// edge and real screen-space refraction. The background sample is displaced by
// the view-space normal; the remaining material blocks stay out of this pass.

group_uniforms gel;
uniform vec4 gel_color : source_color = vec4(0.78, 0.82, 0.92, 1.0);
uniform float center_opacity : hint_range(0.0, 1.0) = 0.24;
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.78;
uniform float edge_density : hint_range(0.0, 1.0) = 0.38;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.4;

group_uniforms refraction;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float refraction_strength : hint_range(0.0, 0.08) = 0.018;
uniform float refraction_mix : hint_range(0.0, 1.0) = 0.9;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.16;
uniform float specular : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	float density = fresnel * edge_density;
	vec2 refraction_offset = NORMAL.xy * refraction_strength * (0.55 + fresnel * 0.45);
	vec2 refraction_uv = clamp(SCREEN_UV + refraction_offset, vec2(0.001), vec2(0.999));
	vec3 refracted_background = texture(screen_texture, refraction_uv).rgb;
	vec3 surface_tint = mix(gel_color.rgb, vec3(1.0), density * 0.48);
	ALBEDO = mix(surface_tint, refracted_background, refraction_mix * (1.0 - fresnel * 0.35));
	ROUGHNESS = roughness;
	SPECULAR = specular;
	ALPHA = gel_color.a * mix(center_opacity, edge_opacity, fresnel);
}
