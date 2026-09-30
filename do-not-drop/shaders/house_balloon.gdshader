shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx, fog_disabled;

// The yellow balloon over a house still waiting for its box
// (house_waiting_marker.gd, N-318.2). It used to be unshaded: a flat yellow
// disc with no volume. Now it takes the sun and the moon like any surface,
// plus a glow of its own that is brighter on top and fades toward the
// underside, and a fresnel edge. The glow is what keeps it round when the
// light is behind it (the faint moon usually is) and what keeps it a warm
// spot on a dark sky; `glow` is set per darkness by the script.
// Fog is off: it would wash the balloon to the grey of the sky.
// Cost: no textures, ~20 ALU per fragment; a few hundred pixels per house.

group_uniforms surface;
uniform vec4 albedo : source_color = vec4(1.0, 0.682, 0.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.35;

group_uniforms glow;
// Emission as a share of the albedo, on top (day ~0.45, night ~0.8).
uniform float glow : hint_range(0.0, 2.0) = 0.45;
// Share of that glow left on the underside: the top-lit look.
uniform float glow_underside : hint_range(0.0, 1.0) = 0.35;
// Brightness of the fresnel edge, and how thin it is.
uniform float rim_glow : hint_range(0.0, 2.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
// How far the edge goes from the balloon's colour toward white.
uniform float rim_whiten : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	float top = smoothstep(-0.7, 0.9, up);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = albedo.rgb * glow * mix(glow_underside, 1.0, top)
		+ mix(albedo.rgb, vec3(1.0), rim_whiten) * rim * rim_glow;
}
