shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

// Mud thrown over the windshield, seen from the cab (tareas de Nacho N-113,
// low_visibility_event.gd + windshield_rain.gd). UV spans the glass: x left
// to right, y bottom to top, the same frame windshield_rain.gdshader uses, so
// both overlays share one mesh.
//
// Cheap on purpose (GL Compatibility, a full-screen-ish transparent quad):
// one 3x3 loop over a coarse grid of big splats (each with a drip running
// down from it), one cell of fine spatter, one value-noise film. No textures.
// `coverage` (0..1) is the event's fade in and out; the splats grow into
// place as it rises, so the glass fills before the driver's eyes.
//
// The wipers thin the mud rather than erase it: every stroke since the mud
// landed lifts CLEAR_PER_STROKE of it where a blade passed, up to
// MAX_CLEARED, so the driver still needs a guide. The blades' motion is the
// same formula as windshield_rain.gdshader (last_sweep() is copied from it;
// test_low_visibility_event checks the two stay identical).

uniform float coverage : hint_range(0.0, 1.0) = 0.0;
// Different splats for each event (the script counts them).
uniform float pattern = 0.0;
// 1 by day, less at dusk and night: unshaded mud would glow.
uniform float brightness : hint_range(0.0, 1.0) = 1.0;
uniform vec3 mud_dark : source_color = vec3(0.2, 0.135, 0.08);
uniform vec3 mud_wet : source_color = vec3(0.36, 0.26, 0.16);

// The wipers, same uniforms and meaning as the rain shader's.
uniform float wiper_time = 0.0;
uniform float wiper_period = 1.6;
uniform float wiper_sweep = 1.7;
uniform vec2 pivot_a = vec2(0.18, 0.02);
uniform vec2 pivot_b = vec2(0.58, 0.02);
uniform float blade_reach = 0.75;
uniform float aspect = 3.0;
uniform float wipers_on = 0.0;
// The wipers' clock (wiper_time) when this mud landed.
uniform float mud_since = 0.0;

const float CLEAR_PER_STROKE = 0.2;
const float MAX_CLEARED = 0.7;
// Glass heights: splat grid and the biggest splat's radius.
const float CELL = 0.5;
const float MAX_SPLAT = 0.4;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The last time before `now` a blade on `pivot` swept over point `p`, or
// -1e6 if the blade doesn't reach it.
float last_sweep(vec2 p, vec2 pivot, float now) {
	vec2 v = vec2((p.x - pivot.x) * aspect, p.y - pivot.y);
	float reach = length(v);
	if (reach > blade_reach || wipers_on < 0.5) {
		return -1e6;
	}
	// Angle up from the bottom edge, measured from +x (where the blade rests).
	float angle = atan(v.y, v.x);
	if (angle < 0.0 || angle > wiper_sweep) {
		return -1e6;
	}
	float base = acos(clamp(1.0 - 2.0 * angle / wiper_sweep, -1.0, 1.0)) / (2.0 * PI) * wiper_period;
	float cycle = floor(now / wiper_period) * wiper_period;
	float best = -1e6;
	for (int k = -1; k <= 0; k++) {
		float start = cycle + float(k) * wiper_period;
		float up = start + base;
		float down = start + wiper_period - base;
		if (up <= now) { best = max(best, up); }
		if (down <= now) { best = max(best, down); }
	}
	return best;
}

void fragment() {
	vec2 p = UV;
	// Isotropic space: the glass is `aspect` tall units wide and 1 high.
	vec2 q = vec2(p.x * aspect, p.y);
	vec2 seed = vec2(pattern * 3.17, pattern * 1.91);
	float density = 0.0;
	// Big splats and their drips, this cell and its neighbours.
	vec2 cell = floor(q / CELL);
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			vec2 c = cell + vec2(float(dx), float(dy));
			float h = hash(c + seed);
			// Grows in as coverage passes this splat's own threshold.
			float grow = clamp((coverage * 1.5 - h) * 2.4, 0.0, 1.0);
			if (grow <= 0.0) {
				continue;
			}
			vec2 centre = (c + vec2(hash(c + seed + 4.1), hash(c + seed + 8.3))) * CELL;
			float radius = mix(0.16, MAX_SPLAT, hash(c + seed + 2.7)) * grow;
			// A ragged edge, not a circle.
			float ragged = (value_noise(q * 9.0 + seed) - 0.5) * 0.16;
			float dist = length(q - centre) + ragged;
			density = max(density, smoothstep(radius, radius * 0.6, dist));
			// The drip: a thin streak running down from the splat's underside.
			float drip_len = radius * mix(0.8, 2.2, hash(c + seed + 6.6)) * grow;
			float across = abs(q.x - (centre.x + (hash(c + seed + 1.9) - 0.5) * radius));
			float below = centre.y - q.y;
			float drip = smoothstep(0.022, 0.006, across) * step(0.0, below) * smoothstep(drip_len, drip_len * 0.5, below);
			density = max(density, drip * grow);
		}
	}
	// Fine spatter between the big ones.
	vec2 fine_cell = floor(q / 0.07);
	float fine_h = hash(fine_cell + seed + 11.0);
	if (fine_h < coverage * 0.55) {
		vec2 fine_centre = (fine_cell + vec2(0.5) + (vec2(hash(fine_cell + seed + 3.0), hash(fine_cell + seed + 5.0)) - 0.5) * 0.4) * 0.07;
		float fine_r = mix(0.008, 0.026, hash(fine_cell + seed + 9.0));
		density = max(density, smoothstep(fine_r, fine_r * 0.5, length(q - fine_centre)));
	}
	// A thin film everywhere, so the gaps between splats are smeared too.
	float film = smoothstep(0.3, 0.85, value_noise(q * 2.6 + seed)) * 0.42 * coverage;
	density = max(density, film);

	// The wipers thin it where a blade passed since it landed.
	float swept = max(last_sweep(p, pivot_a, wiper_time), last_sweep(p, pivot_b, wiper_time));
	if (swept > mud_since) {
		float strokes = floor((swept - mud_since) / (wiper_period * 0.5)) + 1.0;
		density *= 1.0 - min(strokes * CLEAR_PER_STROKE, MAX_CLEARED);
	}

	// Darker at the heart of a splat, wetter and lighter at its rim.
	float shade = value_noise(q * 5.0 + seed + 20.0);
	vec3 colour = mix(mud_wet, mud_dark, smoothstep(0.25, 0.95, density) * (0.55 + 0.45 * shade));
	ALBEDO = colour * brightness;
	// Never quite opaque: a driver can still tell dark from light.
	float edge = min(min(p.x, 1.0 - p.x), min(p.y, 1.0 - p.y));
	ALPHA = clamp(density, 0.0, 1.0) * 0.94 * smoothstep(0.0, 0.035, edge);
}
