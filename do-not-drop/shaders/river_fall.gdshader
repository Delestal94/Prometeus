shader_type spatial;
// A narrow bridge's waterfalls (route_river_falls.gd), in two parts:
//
// The falling sheet, drawn twice: the body (`layer` 0), deep water with
// streaks of white running down it, and a veil in front of it (`layer` 1),
// only its brightest threads, scrolling faster -- the parallax between them
// is what gives the fall its depth. White where it tips over the lip, white
// water at its foot, ragged edges that flicker as the water runs.
//
// The foam (`pool`) where it lands: churning white carried away from the
// impact (two noise samples advected along the flow and cross-faded, the
// usual flow-map trick, so it never smears), spreading downstream, its edge
// broken up. Worked out in metres (`pool_size`) so it isn't stretched.
//
// Unshaded and without textures, so it looks the same on the GL
// Compatibility renderer everywhere; the light is faked from the view angle.
// Sheet UVs: x across 0..1, y metres along the flow; COLOR.r 0 at the lip, 1
// at the foot; COLOR.g 1 right at the lip. Pool UVs: x across, y from
// upstream (0) to downstream (1).
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 water_color : source_color = vec4(0.47, 0.76, 0.84, 0.82);
uniform vec4 deep_color : source_color = vec4(0.17, 0.4, 0.5, 0.9);
uniform vec4 foam_color : source_color = vec4(0.94, 0.97, 1.0, 0.96);
// Metres per second the streaks run down the sheet.
uniform float flow_speed = 1.9;
uniform float layer = 0.0;
uniform bool pool = false;
// Pool only: its size in metres (across, along) and where the water lands,
// in UV.
uniform vec2 pool_size = vec2(6.0, 9.0);
uniform vec2 impact = vec2(0.5, 0.25);

varying float fall;
varying float lip;


float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}


float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.07 + 5.3) * 0.3 + value_noise(p * 4.3 + 11.9) * 0.15;
}


void vertex() {
	fall = COLOR.r;
	lip = COLOR.g;
}


void fragment() {
	// How squarely the surface faces the camera: grazing reads brighter,
	// like the light catching the water's edge.
	float facing = abs(dot(NORMAL, VIEW));
	if (pool) {
		vec2 m = (UV - impact) * pool_size;
		float dist = length(m);
		// Away from the impact and, more and more, downstream.
		vec2 flow = m / max(dist, 0.001) * 0.8 + vec2(0.0, 0.9);
		float t = TIME * 0.45;
		float phase0 = fract(t);
		float phase1 = fract(t + 0.5);
		float weight = abs(phase0 * 2.0 - 1.0);
		float n = mix(fbm((m - flow * phase0 * 1.4) * 1.3), fbm((m - flow * phase1 * 1.4) * 1.3 + 17.0), weight);
		// Downstream the foam trails out; upstream it stops at the rocks.
		vec2 stretched = vec2(m.x, m.y > 0.0 ? m.y * 0.5 : m.y * 1.6);
		float reach = length(stretched) / (pool_size.x * 0.5);
		float density = 1.0 - smoothstep(0.1, 1.0, reach + (n - 0.5) * 0.45);
		float foam = smoothstep(0.35, 0.72, n * 0.8 + density * 0.55);
		// Boiling white right where the water lands.
		foam = max(foam, (1.0 - smoothstep(0.0, 0.3, reach)) * (0.75 + 0.25 * n));
		ALBEDO = mix(water_color.rgb, foam_color.rgb, foam);
		ALPHA = foam * density * foam_color.a;
	} else {
		float speed = flow_speed * mix(1.0, 1.6, layer);
		float y = UV.y - TIME * speed;
		// Long threads, not blobs: fine across, stretched along the flow.
		float n1 = value_noise(vec2(UV.x * mix(20.0, 34.0, layer), y * 0.45));
		float n2 = value_noise(vec2(UV.x * mix(43.0, 61.0, layer) + 3.1, y * 1.05 + 1.7));
		float n3 = value_noise(vec2(UV.x * 8.0 + 7.7 + layer * 13.0, y * 0.22));
		float streak = n1 * 0.5 + n2 * 0.3 + n3 * 0.2;
		float threads = smoothstep(0.52, 0.8, streak);
		// White where it tips over the lip, white water where it lands.
		float white = max(threads, lip * (0.5 + 0.5 * streak));
		white = max(white, smoothstep(0.62, 1.0, fall) * (0.45 + 0.55 * n2));
		// Ragged sides that flicker as the water runs down them, and a soft
		// start where the stream first shows between the rocks behind the lip.
		float ragged = value_noise(vec2(y * 1.4, layer * 7.0 + (UV.x > 0.5 ? 3.0 : 0.0)));
		float side = min(UV.x, 1.0 - UV.x);
		float edge = smoothstep(0.02 + 0.08 * ragged, 0.12 + 0.14 * ragged, side) * smoothstep(0.0, 1.4, UV.y);
		vec3 body = mix(deep_color.rgb, water_color.rgb, smoothstep(0.25, 0.75, n3 * 0.6 + streak * 0.4));
		vec3 colour = mix(body, foam_color.rgb, white);
		ALBEDO = colour * mix(1.08, 0.9, facing) * mix(0.84, 1.0, smoothstep(0.0, 0.3, side));
		if (layer > 0.5) {
			// The veil: only its white threads, the body shows through.
			ALPHA = white * foam_color.a * 0.85 * edge;
		} else {
			ALPHA = mix(mix(deep_color.a, water_color.a, n3), foam_color.a, white) * edge;
		}
	}
}
