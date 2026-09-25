shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

// Rain on the windshield, seen from the cab (tareas de Nacho N-303,
// windshield_rain.gd). UV spans the glass: x left to right, y bottom to top.
// Drops land in a grid of cells, each on its own clock; a drop is shown from
// the moment it lands until a wiper blade last swept over it. The blades'
// motion is the same formula windshield_rain.gd poses the arms with:
//   angle(t) = sweep * 0.5 * (1 - cos(2 pi t / period)), from lying flat along
//   the bottom edge (0) up the glass. So the glass is cleared exactly where
//   the arms go.

uniform float rain_amount : hint_range(0.0, 1.0) = 1.0;
// Seconds the wipers have been running (the script's clock, not TIME, so the
// arms and the cleared glass never drift apart).
uniform float wiper_time = 0.0;
uniform float wiper_period = 1.6;
uniform float wiper_sweep = 1.7;
// Blade pivots (UV) and the blade's reach, in glass heights; aspect is the
// glass's width over its height, to measure angles on the real glass.
// Both blades rest lying toward +x and sweep up together (a tandem pair).
uniform vec2 pivot_a = vec2(0.18, 0.02);
uniform vec2 pivot_b = vec2(0.58, 0.02);
uniform float blade_reach = 0.75;
uniform float aspect = 3.0;
uniform float wipers_on = 1.0;
uniform vec2 cells = vec2(26.0, 9.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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
	float now = wiper_time;
	float swept = max(last_sweep(p, pivot_a, now), last_sweep(p, pivot_b, now));
	vec2 cell = floor(p * cells);
	float alpha = 0.0;
	vec3 colour = vec3(0.0);
	// This cell and its neighbours, so a drop can spill over a cell edge.
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			vec2 c = cell + vec2(float(dx), float(dy));
			float r = hash(c);
			if (r > rain_amount) {
				continue;
			}
			float period = mix(0.7, 2.6, hash(c + 3.1));
			float offset = hash(c + 7.7) * period;
			float landed = floor((now - offset) / period) * period + offset;
			if (landed < swept) {
				continue;
			}
			float age = now - landed;
			vec2 centre = (c + vec2(hash(c + 1.3), hash(c + 5.9))) / cells;
			// Big drops creep down the glass.
			float size = mix(0.004, 0.011, hash(c + 9.4));
			centre.y -= age * size * 1.6;
			vec2 d = vec2((p.x - centre.x) * aspect, p.y - centre.y);
			float dist = length(d) / size;
			if (dist < 1.0) {
				// Water, not soot: a pale, mostly clear body that catches the
				// sky, a thin slightly darker rim where the drop bends the
				// light, and a bright glint. Light over dark road, and only a
				// faint film over bright sky.
				float rim = smoothstep(0.7, 1.0, dist);
				float glint = 1.0 - smoothstep(0.0, 0.3, length(d / size - vec2(-0.3, 0.35)));
				float edge = smoothstep(1.0, 0.88, dist);
				vec3 body = mix(vec3(0.78, 0.84, 0.9), vec3(0.42, 0.47, 0.52), rim);
				float a = mix(0.16, 0.34, rim) * edge;
				// The drop's own colour, and ALPHA says how much of it shows.
				// (Mixing it into the starting black by that alpha first, then
				// applying the alpha again, drew every drop at a fifth of its
				// brightness: dark soot.)
				float drop_alpha = max(a, glint * 0.75);
				if (drop_alpha > alpha) {
					colour = mix(body, vec3(1.0), glint);
					alpha = drop_alpha;
				}
			}
		}
	}
	// Nothing right at the glass's edges, where the frame's trim overlaps it.
	float edge = min(min(p.x, 1.0 - p.x), min(p.y, 1.0 - p.y));
	ALBEDO = colour;
	ALPHA = alpha * smoothstep(0.0, 0.035, edge);
}
