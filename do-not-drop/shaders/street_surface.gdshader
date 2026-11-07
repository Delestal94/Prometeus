shader_type spatial;
render_mode diffuse_burley;

// The company map's streets (expansion D-0304.1b): the roadway and the verge of every piece EdgePieces
// lays, drawn by the street's surface instead of RouteSegment's flat colour boxes (N-323). StreetSurface
// (scripts/gameplay/districts/street_surface.gd) makes one material per surface and puts it on the boxes.
// Everything that is grain or pattern is read in world space, so it runs on across the joints between
// pieces and between a curve's chords, and two boxes that overlap there draw the same colour (no flicker).
// The box's own x (0 on the centre line, +-6 at the edges of the 12 m roadway) places the wheel tracks.
// Palette: route_terrain.gdshader's asphalt, gravel, earth and grass, so a street of the company world
// reads as the same road as the delivery run's.

group_uniforms surface;
// 0 asphalt, 1 gravel, 2 dirt, 3 cobble, 4 verge (the ground box either side of the roadway).
uniform int surface : hint_range(0, 4) = 0;
// Half the roadway a piece draws (m): RouteSegment's Road box is 12 m wide.
uniform float half_width : hint_range(1.0, 12.0) = 6.0;
// Where the wheels run, from the centre of each lane (m): a van's track is about 1.8 m.
uniform float track_offset : hint_range(0.3, 1.5) = 0.85;

group_uniforms detail;
// Greyscale grain maps (art/tools/make_detail_textures.py), the terrain's: white (no-op) when missing.
uniform sampler2D asphalt_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
// Metres covered by one repeat of each map.
uniform float asphalt_tile = 4.0;
uniform float gravel_tile = 2.0;
uniform float earth_tile = 3.0;
uniform float stone_tile = 1.5;
uniform float grass_tile = 3.5;
// Detail maps average ~0.86; this brings the average back to 1.
uniform float detail_gain = 1.16;

group_uniforms cobble;
// One granite sett (m): long across x, rows along z, every other row shifted half a stone.
uniform vec2 sett_size = vec2(0.42, 0.24);
// Half the joint between setts (m).
uniform float joint = 0.022;

varying vec3 world_position;
varying float lateral;
varying float facing_up;

float noise2(vec2 p) {
	return sin(p.x * 1.17 + sin(p.y * 0.83)) * 0.5 + sin(p.y * 1.61 - p.x * 0.71) * 0.25;
}

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

// 1 on the wheel tracks of both lanes, 0 between them.
float wheel_tracks(float x, float wobble) {
	float lane = half_width * 0.5;
	float a = abs(abs(x) - (lane - track_offset));
	float b = abs(abs(x) - (lane + track_offset));
	return 1.0 - smoothstep(0.22, 0.55, min(a, b) + wobble);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lateral = VERTEX.x;
	facing_up = (MODEL_NORMAL_MATRIX * NORMAL).y;
}

vec3 asphalt(vec2 p, float broad, float grain) {
	float detail = texture(asphalt_detail, p / asphalt_tile).r * detail_gain;
	vec3 colour = vec3(0.205, 0.244, 0.251) * detail + grain * 0.009;
	// Patches of newer, darker asphalt and polished wheel paths.
	float repair = smoothstep(0.55, 0.62, noise2(p * 0.045 + 3.1) + broad * 0.2);
	colour *= 1.0 - repair * 0.12;
	colour *= 1.0 - wheel_tracks(lateral, broad * 0.15) * 0.06;
	// A crumbly, paler edge.
	float edge = smoothstep(half_width - 0.5, half_width - 0.05, abs(lateral) + grain * 0.12);
	return mix(colour, colour * 1.18 + vec3(0.02, 0.018, 0.012), edge);
}

vec3 gravel(vec2 p, float broad, float grain) {
	float fine = texture(gravel_detail, p / gravel_tile).r * detail_gain;
	float coarse = texture(gravel_detail, p / (gravel_tile * 0.55) + 0.37).r * detail_gain;
	vec3 base = vec3(0.48, 0.415, 0.30) + broad * 0.02;
	float tracks = wheel_tracks(lateral, grain * 0.1 + broad * 0.2) * (0.75 + broad * 0.25);
	// The wheels pack it down: a little darker and finer. Between them and at the edges, loose stones.
	vec3 compact = base * 0.92 * mix(fine, 1.0, 0.4);
	vec3 loose = base * 1.03 * fine * mix(1.0, coarse, 0.6);
	vec3 colour = mix(loose, compact, tracks);
	float berm = smoothstep(half_width - 1.4, half_width - 0.3, abs(lateral) + grain * 0.2);
	return mix(colour, base * 1.08 * coarse, berm * 0.7);
}

vec3 lawn(vec2 p, float broad, float grain) {
	float grass = texture(grass_detail, p / grass_tile).r * texture(grass_detail, p / (grass_tile * 3.7) + 0.31).r;
	vec3 colour = mix(vec3(0.285, 0.43, 0.205), vec3(0.41, 0.54, 0.27), broad * 0.5 + 0.5);
	return colour * grass * detail_gain * detail_gain + grain * 0.006;
}

vec3 dirt(vec2 p, float broad, float grain) {
	float detail = texture(earth_detail, p / earth_tile).r * detail_gain;
	vec3 colour = (vec3(0.43, 0.355, 0.25) + broad * 0.025 + grain * 0.012) * detail;
	// Ruts: darker and damp where the wheels go.
	float ruts = wheel_tracks(lateral, grain * 0.12 + broad * 0.15);
	colour = mix(colour, colour * vec3(0.7, 0.68, 0.66), ruts);
	// Grass grows where no wheel goes: on the crown between the lanes and along the edges.
	float crown = 1.0 - smoothstep(0.35, 0.8, abs(lateral) + noise2(p * 1.3) * 0.25);
	float side = smoothstep(half_width - 1.6, half_width - 0.2, abs(lateral) + noise2(p * 0.9) * 0.45);
	float tufts = smoothstep(-0.2, 0.4, noise2(p * 2.3) + broad * 0.4);
	return mix(colour, lawn(p, broad, grain), clamp(max(crown * 0.75, side) * tufts, 0.0, 1.0));
}

vec3 cobble(vec2 p, float broad, float grain) {
	vec2 q = p / sett_size;
	float row = floor(q.y);
	q.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(q);
	vec2 inside = fract(q);
	// Metres to the nearest joint.
	vec2 to_edge = min(inside, 1.0 - inside) * sett_size;
	float d = min(to_edge.x, to_edge.y);
	float aa = max(fwidth(d), 0.0005);
	float stone = smoothstep(joint - aa, joint + aa, d);
	float rounded = mix(0.8, 1.0, smoothstep(joint, joint + 0.045, d));
	float tone = hash(cell);
	float grain_map = texture(stone_detail, p / stone_tile).r * detail_gain;
	vec3 dark = vec3(0.35, 0.34, 0.32);
	vec3 light = vec3(0.48, 0.44, 0.385);
	vec3 granite = mix(dark, light, tone) * (0.94 + hash(cell + 17.3) * 0.12) * grain_map;
	vec3 mortar = vec3(0.21, 0.205, 0.185) + grain * 0.01;
	vec3 colour = mix(mortar, granite * rounded, stone);
	// Far away the setts are finer than a pixel: their contrast fades into what they average to (the joints
	// take about 2 * joint * (1 / width + 1 / depth) of the street), so they do not shimmer.
	float joints = clamp(2.0 * joint * (1.0 / sett_size.x + 1.0 / sett_size.y), 0.0, 1.0);
	vec3 average = mix(mix(dark, light, 0.5) * 0.93 * grain_map, mortar, joints);
	float far = smoothstep(0.12, 0.75, max(fwidth(q.x), fwidth(q.y)));
	colour = mix(colour, average, far);
	// The wheels polish it a little.
	return colour * (1.0 + wheel_tracks(lateral, broad * 0.15) * 0.05);
}

void fragment() {
	vec2 p = world_position.xz;
	float broad = noise2(p * 0.15);
	float grain = noise2(p * 7.0);
	vec3 colour;
	if (surface == 1) {
		colour = gravel(p, broad, grain);
	} else if (surface == 2) {
		colour = dirt(p, broad, grain);
	} else if (surface == 3) {
		colour = cobble(p, broad, grain);
	} else if (surface == 4) {
		float earth = texture(earth_detail, p / earth_tile).r * detail_gain;
		vec3 bare = (vec3(0.46, 0.435, 0.325) + broad * 0.025) * earth;
		colour = mix(lawn(p, broad, grain), bare, smoothstep(0.35, 0.75, noise2(p * 0.21 + 7.7)) * 0.6);
	} else {
		colour = asphalt(p, broad, grain);
	}
	// The sides of the slab (and of the verge's box): the same material in shade, earthier.
	float side = 1.0 - smoothstep(0.35, 0.7, abs(facing_up));
	colour = mix(colour, colour * vec3(0.62, 0.6, 0.56), side);
	ALBEDO = colour;
	ROUGHNESS = surface == 0 ? 0.88 : 0.97;
}
