shader_type spatial;
render_mode diffuse_burley, depth_draw_opaque;

// The mud of MudSegment (N-108, look in N-322): one surface over the road
// with the churned strip, the wetter pit, two tyre ruts with tread marks and
// water standing in the low spots, all worked out here instead of flat boxes.
// Its outline is ragged (discard), so it reads as mud spilled over the road
// and not as a slab laid on it. Noise runs in the segment's own frame (the
// mesh is built in it), so every peer and every mud stretch looks the same;
// the grain map runs in world space like route_terrain.gdshader's.

// Same greyscale grain map as the terrain's earth (art/tools/make_detail_textures.py).
uniform sampler2D earth_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float earth_tile = 2.2;
// Segment frame: the stretch runs from z = 0 to z = -stretch_length, the pit between
// -pit_start and -pit_end; the mud reaches mud_half_width either side.
uniform float stretch_length = 60.0;
uniform float pit_start = 18.0;
uniform float pit_end = 30.0;
uniform float mud_half_width = 5.0;
uniform float rut_offset = 1.7;
// 1 for a lump of churned mud (MudMound): no outline, ruts, pit or puddles.
uniform float lump = 0.0;

const vec3 CRUST = vec3(0.43, 0.34, 0.235);
const vec3 MUD = vec3(0.335, 0.245, 0.16);
const vec3 WET = vec3(0.225, 0.158, 0.10);
const vec3 RUT = vec3(0.175, 0.125, 0.082);
// Muddy water: brown, not a mirror.
const vec3 WATER = vec3(0.2, 0.15, 0.1);

varying vec3 local_position;
varying vec3 world_position;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.07 + 17.3) * 0.3 + value_noise(p * 4.31 + 41.7) * 0.15;
}

// 0 in the approach, 1 deep in the pit, with a ragged boundary.
float pit_amount(vec2 p) {
	float along = -p.y;
	float wobble = (value_noise(p * 0.45 + 5.0) - 0.5) * 3.0;
	return smoothstep(pit_start - 2.5, pit_start + 1.5, along + wobble)
			* (1.0 - smoothstep(pit_end - 1.5, pit_end + 2.5, along - wobble));
}

// Distance to the nearest rut's centre line; the ruts wander a little.
float rut_distance(vec2 p) {
	float drift = sin(p.y * 0.11) * 0.3 + (value_noise(vec2(3.1, p.y * 0.35)) - 0.5) * 0.35;
	return min(abs(p.x - rut_offset - drift), abs(p.x + rut_offset - drift));
}

// How deep the ruts are here: they come and go, so from above they read as
// tracks and not as rails.
float rut_amount(vec2 p) {
	float d = rut_distance(p);
	// Each rut on its own: the left and right ones fade in different places.
	float depth = smoothstep(0.2, 0.65, value_noise(vec2(sign(p.x) * 5.0, p.y * 0.2) + 7.0));
	return (1.0 - smoothstep(0.18, 0.46, d)) * depth;
}

// Height of the surface's relief (only for shading: the mesh stays flat).
float relief(vec2 p, float pit) {
	float clumps = fbm(p * 1.4);
	if (lump > 0.5) {
		return clumps;
	}
	float d = rut_distance(p);
	float rut = rut_amount(p);
	// The mud squeezed out of each rut piles up along its sides.
	float ridge = smoothstep(0.32, 0.5, d) * (1.0 - smoothstep(0.55, 0.95, d));
	// Tread: chevrons pressed across the rut.
	float tread = sin((p.y + abs(fract(p.x * 0.5 + 0.5) - 0.5) * 1.2) * 18.0) * 0.5 + 0.5;
	return clumps * mix(0.7, 0.35, pit) - rut * 0.9 + ridge * 0.55 + tread * rut * 0.18;
}

void vertex() {
	local_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = local_position.xz;
	float pit = lump > 0.5 ? 0.0 : pit_amount(p);
	// Distance inside the outline, in metres (big for a lump).
	float inside = 10.0;
	if (lump < 0.5) {
		// Ragged outline: wider in the pit, tapering in at both ends. Only
		// broad noise, so far away the edge stays a clean wavy line.
		float edge_noise = (value_noise(p * 0.35) * 0.65 + value_noise(p * 0.9 + 3.0) * 0.35 - 0.5) * 2.0;
		float half_width = mud_half_width + pit * 0.5 + edge_noise * 0.9;
		float along = -p.y;
		float ends = min(along, stretch_length - along) - 1.2 - (value_noise(p * 0.5 + 9.0) - 0.5) * 2.6;
		inside = min(half_width - abs(p.x), ends);
		if (inside < 0.0) {
			discard;
		}
	}
	// A drier, paler crust along the outline eases it into the road.
	float rim = 1.0 - smoothstep(0.0, 0.8, inside);
	float h = relief(p, pit);
	const float STEP = 0.04;
	float dx = (relief(p + vec2(STEP, 0.0), pit) - h) / STEP;
	float dz = (relief(p + vec2(0.0, STEP), pit) - h) / STEP;
	// The mesh's own normal stays up after conform_geometry (terrain_field.gd),
	// so the bump is built around the model's up and turned with it below.
	vec3 bumped = vec3(-dx * 0.07, 1.0, -dz * 0.07);
	float grain = texture(earth_detail, world_position.xz / earth_tile).r;
	grain = mix(1.0, grain * 1.16, 0.65);
	float clumps = fbm(p * 1.4);
	float rut = lump > 0.5 ? 0.0 : rut_amount(p);
	// Wet where it is low: the pit, the ruts, and the hollows between clumps.
	float wet = clamp(pit * 0.75 + rut * 0.7 + (1.0 - smoothstep(0.3, 0.55, clumps)) * 0.45, 0.0, 1.0);
	vec3 colour = mix(MUD, CRUST, smoothstep(0.55, 0.8, clumps) * (1.0 - pit * 0.7));
	colour = mix(colour, WET, wet * 0.8);
	colour = mix(colour, RUT, rut * 0.6);
	colour = mix(colour, CRUST * 1.06, rim * 0.7);
	wet *= 1.0 - rim;
	colour *= grain;
	// Standing water in the lowest spots: dark, still, and the only glossy part.
	float water_noise = fbm(p * 0.55 + 23.0) + rut * 0.2 + pit * 0.12 - rim * 0.5;
	float water = lump > 0.5 ? 0.0 : smoothstep(0.74, 0.77, water_noise);
	colour = mix(colour, WATER, water);
	ALBEDO = colour;
	// A soft sheen, not a mirror: a mirror shows the sky and turns it blue-black.
	ROUGHNESS = mix(mix(0.92, 0.55, wet), 0.28, water);
	SPECULAR = mix(0.4, 0.32, water);
	// Water lies flat: it flattens the bump under it.
	bumped = normalize(mix(bumped, vec3(0.0, 1.0, 0.0), water));
	vec3 bump_view = (VIEW_MATRIX * MODEL_MATRIX * vec4(bumped, 0.0)).xyz;
	// A lump keeps its own rounded shading and only takes the clumps on top.
	vec3 lump_view = NORMAL + (VIEW_MATRIX * MODEL_MATRIX * vec4(bumped.x, 0.0, bumped.z, 0.0)).xyz;
	NORMAL = normalize(lump > 0.5 ? lump_view : bump_view);
}
