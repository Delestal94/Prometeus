shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

// S-311.27-34: GL Compatibility gelatin with a clear centre, a denser Fresnel
// edge, real screen-space refraction, studio highlights and Beer-Lambert-style
// absorption driven by the baked base-body thickness map. Wrapped diffuse and
// back-light transmission add a single-pass fake subsurface glow. Sparse 3D
// object-space noise adds internal motes without camera or UV swimming. An
// alpha depth pre-pass stabilizes self-overlap and a thinner shadow pass keeps
// the translucent body's shadow lighter than an opaque character's. Per-instance
// colour, opacity, brightness and constant-volume squash/stretch keep one
// shared material for every player.

instance uniform vec4 gel_color : source_color = vec4(0.78, 0.82, 0.92, 1.0);
instance uniform float gel_opacity : hint_range(0.0, 1.0) = 1.0;
// Values >= 2 pack a 15-bit team colour above the fractional brightness.
instance uniform float gel_brightness : hint_range(0.5, 1.5) = 1.0;
// Packed to stay within Godot's 16 instance-uniform limit:
// surface = absorption, shine, skin effect mode plus general-thickness weight,
// effect amount. Negative X/Y keep the shared material's legacy absorption and
// shine until a skin applies. The mode's fractional offset is weight * 0.25.
instance uniform vec4 gel_skin_surface = vec4(-1.0, -1.0, 0.0, 0.0);
// interior = RGB feature colour plus object-space feature scale.
instance uniform vec4 gel_interior = vec4(0.0, 0.0, 0.0, 8.0);
instance uniform float gel_squash_stretch : hint_range(-0.2, 0.2) = 0.0;
instance uniform vec3 gel_contact_direction = vec3(1.0, 0.0, 0.0);
// Positive = contact compression. Negative values pack knockout cause in the
// integer part and transition amount in the fraction, preserving 16 uniforms.
instance uniform float gel_contact_compression : hint_range(-6.0, 1.25) = 0.0;
instance uniform vec4 gel_wave_0 = vec4(0.0, 0.0, 0.0, -1.0);
instance uniform vec4 gel_wave_1 = vec4(0.0, 0.0, 0.0, -1.0);
instance uniform vec4 gel_wave_2 = vec4(0.0, 0.0, 0.0, -1.0);
instance uniform vec4 gel_wave_3 = vec4(0.0, 0.0, 0.0, -1.0);
instance uniform vec4 gel_wave_strengths = vec4(0.0);
instance uniform vec4 gel_inertia = vec4(0.0);
instance uniform vec4 gel_wind = vec4(0.0);
instance uniform vec4 gel_weather = vec4(0.0);

group_uniforms gel;
uniform float center_opacity : hint_range(0.0, 1.0) = 0.24;
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.78;
uniform float edge_density : hint_range(0.0, 1.0) = 0.38;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.4;

group_uniforms refraction;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float refraction_strength : hint_range(0.0, 0.08) = 0.018;
uniform float refraction_mix : hint_range(0.0, 1.0) = 0.9;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.08;
uniform float specular : hint_range(0.0, 1.0) = 0.9;

group_uniforms subsurface_backlight;
uniform float subsurface_wrap : hint_range(0.0, 1.0) = 0.42;
uniform float backlight_strength : hint_range(0.0, 3.0) = 1.35;
uniform float backlight_power : hint_range(1.0, 8.0) = 2.4;

group_uniforms internal_inclusions;
uniform float inclusion_density : hint_range(0.0, 0.4) = 0.18;
uniform float inclusion_scale : hint_range(8.0, 128.0) = 72.0;
uniform float inclusion_contrast : hint_range(0.0, 0.3) = 0.07;

group_uniforms transparency_shadows;
uniform float shadow_density : hint_range(0.1, 1.0) = 0.32;

group_uniforms thickness_absorption;
uniform sampler2D thickness_map : repeat_disable, filter_linear;
uniform float thickness_decode_meters : hint_range(0.0, 3.0) = 2.0;
uniform float absorption_coefficient : hint_range(0.0, 8.0) = 2.4;
uniform float absorption_color_mix : hint_range(0.0, 1.0) = 0.62;
uniform float absorption_opacity : hint_range(0.0, 1.0) = 0.34;

group_uniforms studio_reflection;
uniform vec4 studio_reflection_color : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform float studio_reflection_strength : hint_range(0.0, 2.0) = 1.1;
uniform float studio_reflection_softness : hint_range(0.002, 0.08) = 0.008;
uniform float studio_ribbon_width : hint_range(0.005, 0.12) = 0.026;

varying vec3 model_position;

float box_mask(vec2 point, vec2 centre, vec2 half_size, float softness) {
	vec2 delta = abs(point - centre) - half_size;
	float distance_to_box = max(delta.x, delta.y);
	return 1.0 - smoothstep(-softness, softness, distance_to_box);
}

float hash_object_cell(vec3 cell) {
	cell = fract(cell * 0.1031);
	cell += dot(cell, cell.yzx + 33.33);
	return fract((cell.x + cell.y) * cell.z);
}

float object_noise_3d(vec3 point) {
	vec3 cell = floor(point);
	vec3 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float near_z = mix(
		mix(hash_object_cell(cell), hash_object_cell(cell + vec3(1.0, 0.0, 0.0)), blend.x),
		mix(hash_object_cell(cell + vec3(0.0, 1.0, 0.0)), hash_object_cell(cell + vec3(1.0, 1.0, 0.0)), blend.x),
		blend.y
	);
	float far_z = mix(
		mix(hash_object_cell(cell + vec3(0.0, 0.0, 1.0)), hash_object_cell(cell + vec3(1.0, 0.0, 1.0)), blend.x),
		mix(hash_object_cell(cell + vec3(0.0, 1.0, 1.0)), hash_object_cell(cell + vec3(1.0, 1.0, 1.0)), blend.x),
		blend.y
	);
	return mix(near_z, far_z, blend.z);
}

float weather_rain() {
	return mod(gel_weather.z, 2.0);
}

float weather_night() {
	return clamp(floor(gel_weather.z * 0.5) * 0.5, 0.0, 1.0);
}

float skin_brightness() {
	return gel_brightness >= 2.0 ? mod(gel_brightness, 2.0) : gel_brightness;
}

float team_accent_enabled() {
	return step(2.0, gel_brightness);
}

vec3 team_accent_color() {
	float color_code = max(floor(gel_brightness * 0.5) - 1.0, 0.0);
	float red = mod(color_code, 32.0);
	float green = mod(floor(color_code / 32.0), 32.0);
	float blue = floor(color_code / 1024.0);
	return vec3(red, green, blue) / 31.0;
}

float team_accent_signature() {
	float color_code = max(floor(gel_brightness * 0.5) - 1.0, 0.0);
	float red = mod(color_code, 32.0);
	float green = mod(floor(color_code / 32.0), 32.0);
	float blue = floor(color_code / 1024.0);
	return mod(red + green * 8.0 + blue * 10.0, 11.0);
}

float general_thickness_weight() {
	float skin_mode = floor(gel_skin_surface.z + 0.5);
	return clamp((gel_skin_surface.z - skin_mode) * 4.0, -1.0, 1.0);
}

float team_core_mask(vec3 point) {
	float vertical = smoothstep(0.74, 0.80, point.y) * (1.0 - smoothstep(1.20, 1.26, point.y));
	float horizontal = 1.0 - smoothstep(0.19, 0.29, abs(point.x));
	return vertical * horizontal;
}

vec3 team_core_color(vec3 team_color, vec3 point) {
	float band = floor(clamp((point.y - 0.76) / 0.12, 0.0, 3.0));
	float bit = mod(floor(team_accent_signature() / pow(2.0, band)), 2.0);
	return mix(team_color * 0.22, mix(team_color, vec3(1.0), 0.28), bit);
}

vec3 animated_spectrum(float phase) {
	return 0.5 + 0.5 * cos(6.28318 * (phase + vec3(0.0, 0.333, 0.667)));
}

float animated_lava_mask(vec3 point) {
	vec3 flow_point = point * vec3(gel_interior.a * 0.65, gel_interior.a * 0.42, gel_interior.a * 0.65);
	flow_point.y -= TIME * (0.05 + gel_skin_surface.w * 0.08);
	return smoothstep(0.48, 0.72, object_noise_3d(flow_point));
}

vec3 animated_skin_tint(vec3 base_tint, vec3 point) {
	if (gel_skin_surface.z > 5.5 && gel_skin_surface.z < 6.5) {
		float phase = point.y * gel_interior.a * 0.16 - TIME * (0.08 + gel_skin_surface.w * 0.18);
		return mix(base_tint, animated_spectrum(phase + gel_weather.y), gel_skin_surface.w);
	}
	if (gel_skin_surface.z > 6.5 && gel_skin_surface.z < 7.5) {
		float pulse = 0.86 + sin(TIME * 2.0 + gel_weather.y * 6.28318) * 0.14;
		return mix(base_tint, gel_interior.rgb * pulse, weather_night() * gel_skin_surface.w * 0.55);
	}
	if (gel_skin_surface.z > 7.5 && gel_skin_surface.z < 8.5) {
		return mix(base_tint, gel_interior.rgb, animated_lava_mask(point) * gel_skin_surface.w);
	}
	return base_tint;
}

vec3 random_cell_point(vec3 cell) {
	return vec3(
		hash_object_cell(cell + vec3(11.0, 3.0, 7.0)),
		hash_object_cell(cell + vec3(5.0, 17.0, 13.0)),
		hash_object_cell(cell + vec3(19.0, 23.0, 2.0))
	) * 0.56 + 0.22;
}

vec3 interior_base_tint(vec3 base_tint, vec3 point) {
	if (gel_skin_surface.z > 0.5 && gel_skin_surface.z < 1.5) {
		float upper_layer = smoothstep(0.72, 0.82, point.y);
		return mix(mix(base_tint, gel_interior.rgb, gel_skin_surface.w), base_tint, upper_layer);
	}
	if (gel_skin_surface.z > 1.5 && gel_skin_surface.z < 2.5) {
		float height_mix = smoothstep(0.12, 1.55, point.y) * gel_skin_surface.w;
		return mix(base_tint, gel_interior.rgb, height_mix);
	}
	return animated_skin_tint(base_tint, point);
}

float interior_feature_mask(vec3 point) {
	vec3 grid_point = point * gel_interior.a;
	vec3 cell = floor(grid_point);
	vec3 local_point = fract(grid_point);
	vec3 delta = local_point - random_cell_point(cell);
	if (gel_skin_surface.z > 2.5 && gel_skin_surface.z < 3.5) {
		float chunk_distance = max(max(abs(delta.x), abs(delta.y)), abs(delta.z));
		return 1.0 - smoothstep(0.11, 0.22, chunk_distance);
	}
	if (gel_skin_surface.z > 3.5 && gel_skin_surface.z < 4.5) {
		return 1.0 - smoothstep(0.035, 0.095, length(delta));
	}
	if (gel_skin_surface.z > 4.5 && gel_skin_surface.z < 5.5) {
		float bubble_distance = length(delta);
		float bubble_outer = 1.0 - smoothstep(0.29, 0.36, bubble_distance);
		float bubble_inner = 1.0 - smoothstep(0.2, 0.27, bubble_distance);
		return max(bubble_outer - bubble_inner, 0.0);
	}
	return 0.0;
}

float impact_wave(vec3 point, vec4 wave, float strength) {
	if (wave.w < 0.0 || strength <= 0.0) {
		return 0.0;
	}
	float radius = wave.w * 0.92;
	float phase = (length(point - wave.xyz) - radius) / 0.06;
	float crest = exp(-phase * phase);
	float wake_phase = phase + 1.55;
	float wake = exp(-wake_phase * wake_phase) * 0.34;
	return (crest - wake) * strength * 0.035 * exp(-wave.w * 1.65);
}

float inertial_drag_mask(vec3 point) {
	float head_region = smoothstep(1.24, 1.36, point.y) * (1.0 - smoothstep(0.48, 0.68, abs(point.x)));
	float head_reach = smoothstep(0.12, 0.46, length(point - vec3(0.0, 1.29, 0.0)));
	float arm_region = smoothstep(0.28, 0.40, abs(point.x));
	arm_region *= smoothstep(0.58, 0.76, point.y) * (1.0 - smoothstep(1.34, 1.48, point.y));
	vec3 shoulder = vec3(sign(point.x) * 0.28, 1.17, 0.0);
	float arm_reach = smoothstep(0.08, 0.58, length(point - shoulder));
	return clamp(max(head_region * head_reach, arm_region * arm_reach), 0.0, 1.0);
}

float environment_drop(vec3 point, float offset) {
	float drop_seed = gel_weather.y * 31.0 + offset;
	float age = fract(gel_weather.x * 1.7 + drop_seed);
	vec3 centre = vec3(
		(fract(sin(drop_seed * 12.9898) * 43758.5453) - 0.5) * 0.62,
		mix(0.28, 1.58, fract(sin(drop_seed * 78.233) * 23421.631)),
		(fract(sin(drop_seed * 39.425) * 19341.117) - 0.5) * 0.48
	);
	float ring_distance = length(point - centre) - age * 0.34;
	float ring = exp(-pow(ring_distance / 0.028, 2.0));
	return ring * (1.0 - age) * weather_rain();
}

float environment_ripple(vec3 point) {
	return environment_drop(point, 0.17) + environment_drop(point, 0.53) + environment_drop(point, 0.89);
}

void vertex() {
	float knockout_packed = max(-gel_contact_compression, 0.0);
	float knockout_cause = floor(knockout_packed + 0.0001);
	float knockout = fract(knockout_packed);
	float positive_deformation = max(gel_contact_compression, 0.0);
	float extreme_impact = positive_deformation > 0.2
		? clamp((positive_deformation - 0.75) / 0.5, -1.0, 1.0) : 0.0;
	float contact_compression = positive_deformation > 0.2 ? 0.0 : positive_deformation;
	float drag_mask = inertial_drag_mask(VERTEX);
	vec3 turning_drag = vec3(-VERTEX.z, 0.0, VERTEX.x) * gel_inertia.w;
	VERTEX += (gel_inertia.xyz + turning_drag) * drag_mask;
	float wave_offset = 0.0;
	wave_offset += impact_wave(VERTEX, gel_wave_0, gel_wave_strengths.x);
	wave_offset += impact_wave(VERTEX, gel_wave_1, gel_wave_strengths.y);
	wave_offset += impact_wave(VERTEX, gel_wave_2, gel_wave_strengths.z);
	wave_offset += impact_wave(VERTEX, gel_wave_3, gel_wave_strengths.w);
	VERTEX += NORMAL * clamp(wave_offset, -0.05, 0.07);
	float vertical_scale = max(1.0 + gel_squash_stretch, 0.8);
	float radial_scale = inversesqrt(vertical_scale);
	VERTEX *= vec3(radial_scale, vertical_scale, radial_scale);
	NORMAL = normalize(NORMAL / vec3(radial_scale, vertical_scale, radial_scale));
	vec3 contact_axis = normalize(gel_contact_direction);
	float contact_scale = max(1.0 - contact_compression, 0.82);
	float contact_radial = inversesqrt(contact_scale);
	float contact_position = dot(VERTEX, contact_axis);
	vec3 contact_perpendicular = VERTEX - contact_axis * contact_position;
	VERTEX = (
		contact_axis * contact_position * contact_scale
		+ contact_perpendicular * contact_radial
	);
	float contact_normal = dot(NORMAL, contact_axis);
	NORMAL = normalize(
		contact_axis * contact_normal / contact_scale
		+ (NORMAL - contact_axis * contact_normal) / contact_radial
	);
	// A hard impact uses the same direction and packed uniform, but expands far
	// past ordinary contact before an underdamped rebound. The positive bounds
	// guarantee that neither positions nor normals can invert.
	float extreme_axis_scale = clamp(1.0 - extreme_impact * 0.64, 0.36, 1.65);
	float extreme_radial_scale = inversesqrt(extreme_axis_scale);
	float extreme_position = dot(VERTEX, contact_axis);
	vec3 extreme_perpendicular = VERTEX - contact_axis * extreme_position;
	VERTEX = contact_axis * extreme_position * extreme_axis_scale
		+ extreme_perpendicular * extreme_radial_scale;
	float extreme_normal = dot(NORMAL, contact_axis);
	NORMAL = normalize(
		contact_axis * extreme_normal / extreme_axis_scale
		+ (NORMAL - contact_axis * extreme_normal) / extreme_radial_scale
	);
	float melt = knockout * knockout * (3.0 - 2.0 * knockout);
	float source_height = clamp(VERTEX.y / 1.75, 0.0, 1.0);
	if (knockout_cause < 1.5) {
		// Default melt: a soft, rounded puddle.
		float puddle_spread = mix(1.0, 1.55 + source_height * 0.38, melt);
		float puddle_height = 0.025 + source_height * 0.055;
		VERTEX.xz *= puddle_spread;
		VERTEX.y = mix(VERTEX.y, puddle_height, melt);
		NORMAL = normalize(NORMAL / vec3(puddle_spread, mix(1.0, 0.045, melt), puddle_spread));
	} else if (knockout_cause < 2.5) {
		// Crushed: a broad, even pancake with a thicker rim.
		float pancake_spread = mix(1.0, 1.82 + source_height * 0.24, melt);
		VERTEX.xz *= pancake_spread;
		VERTEX.y = mix(VERTEX.y, 0.045 + source_height * 0.035, melt);
		NORMAL = normalize(NORMAL / vec3(pancake_spread, mix(1.0, 0.035, melt), pancake_spread));
	} else if (knockout_cause < 3.5) {
		// Explosion: the body contracts to a tiny core while droplets carry the silhouette.
		vec3 burst_direction = normalize(VERTEX + vec3(0.13, 0.37, -0.09));
		VERTEX = mix(VERTEX, vec3(0.0, 0.68, 0.0) + burst_direction * 0.055, melt);
	} else if (knockout_cause < 4.5) {
		// Water: dissolve downward into a narrow, rippled remnant.
		float dissolve_wave = sin(VERTEX.x * 15.0 + VERTEX.z * 11.0) * 0.018;
		VERTEX.xz *= mix(1.0, 0.42, melt);
		VERTEX.y = mix(VERTEX.y, -0.12 + source_height * 0.025 + dissolve_wave, melt);
		NORMAL = normalize(NORMAL / vec3(mix(1.0, 0.42, melt), mix(1.0, 0.025, melt), mix(1.0, 0.42, melt)));
	} else {
		// Run over: a low skid stretched strongly along the wheel direction.
		float skid_x = mix(1.0, 2.18, melt);
		float skid_z = mix(1.0, 1.18, melt);
		VERTEX.x = VERTEX.x * skid_x + source_height * melt * 0.34;
		VERTEX.z *= skid_z;
		VERTEX.y = mix(VERTEX.y, 0.035 + source_height * 0.03, melt);
		NORMAL = normalize(NORMAL / vec3(skid_x, mix(1.0, 0.03, melt), skid_z));
	}
	float wind_mask = smoothstep(0.12, 1.55, VERTEX.y);
	float wind_sway = sin(gel_weather.x * 1.35 + gel_weather.y * 6.28318);
	wind_sway = wind_sway * 0.72 + sin(gel_weather.x * 2.1 + gel_weather.y * 3.1) * 0.28;
	VERTEX += gel_wind.xyz * gel_wind.w * wind_mask * wind_sway * 0.025;
	VERTEX += NORMAL * environment_ripple(VERTEX) * 0.008;
	model_position = VERTEX;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	float density = fresnel * edge_density;
	vec3 skin_tint = interior_base_tint(gel_color.rgb, model_position);
	float visual_brightness = skin_brightness();
	vec3 player_tint = skin_tint * visual_brightness * mix(1.0, 1.08, gel_weather.w);
	vec2 refraction_offset = NORMAL.xy * refraction_strength * (0.55 + fresnel * 0.45);
	vec2 refraction_uv = clamp(SCREEN_UV + refraction_offset, vec2(0.001), vec2(0.999));
	vec3 refracted_background = texture(screen_texture, refraction_uv).rgb;
	vec3 surface_tint = mix(player_tint, vec3(1.0), density * 0.48);
	float thickness_morph_scale = 1.0 + general_thickness_weight() * 0.21;
	float thickness_meters = texture(thickness_map, UV).r * thickness_decode_meters
		* thickness_morph_scale;
	float thickness_transmission = exp(-absorption_coefficient * thickness_meters);
	if (gel_skin_surface.x >= 0.0) {
		thickness_transmission = exp(-gel_skin_surface.x * thickness_meters);
	}
	float thickness_absorption = 1.0 - thickness_transmission;
	vec3 absorbed_tint = mix(
		surface_tint,
		player_tint,
		thickness_absorption * absorption_color_mix
	);
	float background_mix = refraction_mix * (1.0 - fresnel * 0.35);
	background_mix *= mix(1.0, thickness_transmission, absorption_color_mix);
	ALBEDO = mix(absorbed_tint, refracted_background, background_mix);
	vec2 matcap_uv = normalize(NORMAL).xy * 0.5 + 0.5;
	float window_reflection = 0.0;
	window_reflection += box_mask(matcap_uv, vec2(0.315, 0.695), vec2(0.038, 0.052), studio_reflection_softness);
	window_reflection += box_mask(matcap_uv, vec2(0.405, 0.695), vec2(0.038, 0.052), studio_reflection_softness);
	window_reflection += box_mask(matcap_uv, vec2(0.315, 0.815), vec2(0.038, 0.052), studio_reflection_softness);
	window_reflection += box_mask(matcap_uv, vec2(0.405, 0.815), vec2(0.038, 0.052), studio_reflection_softness);
	window_reflection *= smoothstep(1.25, 1.36, model_position.y);
	float ribbon = 1.0 - smoothstep(
		studio_ribbon_width,
		studio_ribbon_width + studio_reflection_softness,
		abs(matcap_uv.x - 0.235)
	);
	float arm_gate = smoothstep(0.22, 0.4, abs(model_position.x)) * smoothstep(0.75, 0.95, model_position.y);
	float leg_gate = 1.0 - smoothstep(0.54, 0.76, model_position.y);
	ribbon *= max(arm_gate, leg_gate);
	float studio_mask = clamp(window_reflection + ribbon * 0.55, 0.0, 1.0) * smoothstep(0.08, 0.32, facing);
	ALBEDO = mix(ALBEDO, studio_reflection_color.rgb, studio_mask * 0.4);
	EMISSION = studio_reflection_color.rgb * studio_mask * studio_reflection_strength;
	float inclusion_threshold = mix(1.0, 0.72, inclusion_density);
	float fine_motes = smoothstep(
		inclusion_threshold,
		inclusion_threshold + 0.018,
		object_noise_3d(model_position * inclusion_scale)
	);
	float bubble_field = object_noise_3d(model_position * inclusion_scale * 0.72 + vec3(17.0));
	float bubble_outer = smoothstep(inclusion_threshold - 0.012, inclusion_threshold, bubble_field);
	float bubble_inner = smoothstep(inclusion_threshold + 0.008, inclusion_threshold + 0.02, bubble_field);
	float inclusion_mask = clamp(fine_motes + (bubble_outer - bubble_inner) * 0.7, 0.0, 1.0);
	ALBEDO = mix(ALBEDO, player_tint * 0.82, inclusion_mask * inclusion_contrast);
	float interior_mask = interior_feature_mask(model_position) * gel_skin_surface.w;
	ALBEDO = mix(ALBEDO, gel_interior.rgb * visual_brightness, interior_mask * 0.72);
	if (gel_skin_surface.z > 3.5 && gel_skin_surface.z < 4.5) {
		EMISSION += gel_interior.rgb * interior_mask * 1.4;
	}
	if (gel_skin_surface.z > 6.5 && gel_skin_surface.z < 7.5) {
		float neon_pulse = 0.86 + sin(TIME * 2.0 + gel_weather.y * 6.28318) * 0.14;
		EMISSION += gel_interior.rgb * weather_night() * gel_skin_surface.w * neon_pulse * (0.7 + fresnel);
	}
	if (gel_skin_surface.z > 7.5 && gel_skin_surface.z < 8.5) {
		EMISSION += gel_interior.rgb * animated_lava_mask(model_position) * gel_skin_surface.w * 0.8;
	}
	if (gel_skin_surface.z > 8.5 && gel_skin_surface.z < 9.5) {
		float holo_phase = fresnel * 1.8 + model_position.y * gel_interior.a * 0.15 - TIME * 0.12;
		vec3 holo_color = animated_spectrum(holo_phase + gel_weather.y);
		ALBEDO = mix(ALBEDO, holo_color, gel_skin_surface.w * (0.3 + fresnel * 0.35));
		EMISSION += holo_color * gel_skin_surface.w * (0.08 + fresnel * 0.18);
	}
	float team_edge = team_accent_enabled() * smoothstep(0.08, 0.72, fresnel) * 0.62;
	vec3 team_color = team_accent_color() * visual_brightness;
	ALBEDO = mix(ALBEDO, team_color, team_edge);
	float team_core = team_accent_enabled() * team_core_mask(model_position);
	vec3 team_mark = team_core_color(team_color, model_position);
	ALBEDO = mix(ALBEDO, team_mark, team_core * 0.9);
	EMISSION += team_color * team_edge * 0.1 + team_mark * team_core * (0.08 + weather_night() * 0.38);
	ROUGHNESS = mix(roughness, 0.025, gel_weather.w * 0.75);
	SPECULAR = mix(specular, 1.0, gel_weather.w);
	if (gel_skin_surface.y >= 0.0) {
		float skin_roughness = mix(0.48, 0.025, gel_skin_surface.y);
		ROUGHNESS = mix(skin_roughness, 0.025, gel_weather.w * 0.75);
		SPECULAR = mix(gel_skin_surface.y, 1.0, gel_weather.w);
	}
	float surface_alpha = gel_color.a * gel_opacity * mix(center_opacity, edge_opacity, fresnel);
	float final_alpha = clamp(
		surface_alpha + thickness_absorption * absorption_opacity
			+ inclusion_mask * inclusion_contrast + interior_mask * 0.08,
		0.0,
		1.0
	);
	if (IN_SHADOW_PASS) {
		float shadow_coverage = mix(final_alpha, 1.0, shadow_density);
		float shadow_hash = hash_object_cell(floor(model_position * 180.0));
		if (shadow_hash > shadow_coverage) {
			discard;
		}
		ALPHA = 1.0;
	} else {
		ALPHA = final_alpha;
	}
}

void light() {
	float normal_light = dot(NORMAL, LIGHT);
	float wrapped_light = clamp(
		(normal_light + subsurface_wrap) / (1.0 + subsurface_wrap),
		0.0,
		1.0
	);
	float back_light = pow(clamp(-normal_light, 0.0, 1.0), backlight_power);
	vec3 half_vector = normalize(LIGHT + VIEW);
	float skin_roughness = roughness;
	float skin_specular = specular;
	if (gel_skin_surface.y >= 0.0) {
		skin_roughness = mix(0.48, 0.025, gel_skin_surface.y);
		skin_specular = gel_skin_surface.y;
	}
	float specular_power = mix(128.0, 8.0, skin_roughness);
	float specular_lobe = pow(clamp(dot(NORMAL, half_vector), 0.0, 1.0), specular_power);
	vec3 wrapped_diffuse = ALBEDO * LIGHT_COLOR * wrapped_light;
	vec3 back_scatter_tint = gel_color.rgb * gel_brightness;
	if (team_accent_enabled() > 0.5) {
		back_scatter_tint = gel_color.rgb * skin_brightness();
	}
	vec3 back_scatter = back_scatter_tint * LIGHT_COLOR * back_light * backlight_strength;
	DIFFUSE_LIGHT += (wrapped_diffuse + back_scatter) * ATTENUATION;
	SPECULAR_LIGHT += LIGHT_COLOR * specular_lobe * skin_specular * ATTENUATION;
}
