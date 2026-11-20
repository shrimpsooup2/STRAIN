// Surface ground for the endings: blocky grey dirt, with living green spreading
// out from `center` to `radius` (cell-quantised, ragged edge).
shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_disabled, cull_back;

uniform vec3 center = vec3(0.0);
uniform float radius = 0.0;
uniform float cell = 0.5;
uniform vec4 grey_a : source_color = vec4(0.54, 0.54, 0.52, 1.0);
uniform vec4 grey_b : source_color = vec4(0.46, 0.46, 0.44, 1.0);
uniform vec4 green_a : source_color = vec4(0.29, 0.60, 0.24, 1.0);
uniform vec4 green_b : source_color = vec4(0.23, 0.52, 0.18, 1.0);

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 c = floor(wpos.xz / cell);
	float h = hash(c);
	float d = length((c + 0.5) * cell - center.xz);
	bool g = d < radius + (h - 0.5) * 2.5;
	vec3 col;
	if (g) {
		col = mod(c.x + c.y, 2.0) < 1.0 ? green_a.rgb : green_b.rgb;
	} else {
		col = h < 0.5 ? grey_a.rgb : grey_b.rgb;
	}
	ALBEDO = col;
}
