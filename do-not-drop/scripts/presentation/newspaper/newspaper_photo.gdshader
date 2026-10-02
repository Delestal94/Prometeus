shader_type canvas_item;
// A press photo on newsprint: grey, contrasty, with a visible halftone screen.

uniform vec3 stock = vec3(0.92, 0.89, 0.81);
uniform vec3 print_ink = vec3(0.17, 0.16, 0.15);

void fragment() {
	vec3 source = texture(TEXTURE, UV).rgb;
	float grey = dot(source, vec3(0.299, 0.587, 0.114));
	grey = smoothstep(0.12, 0.88, grey);
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
	// Screen at 45 degrees, like a real halftone.
	vec2 rotated = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * pixel;
	vec2 dot_uv = fract(rotated / 5.0) - 0.5;
	float radius = sqrt(clamp(1.0 - grey, 0.0, 1.0)) * 0.7;
	float ink = 1.0 - smoothstep(radius - 0.08, radius + 0.08, length(dot_uv));
	vec3 continuous = mix(print_ink, stock, grey);
	vec3 screened = mix(stock, print_ink, ink * 0.92);
	COLOR = vec4(mix(continuous, screened, 0.4), 1.0);
}
