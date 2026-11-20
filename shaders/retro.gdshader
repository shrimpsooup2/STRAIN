// Lit low-poly material: per-vertex (Gouraud) lighting, nearest textures,
// and clip-space vertex snapping for the wobbly early-3D look.
shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform bool use_tex = false;
uniform bool use_vcol = false;
uniform float uv_scale = 1.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Snap grid in NDC half-units. 192x108 = exact pixel grid at 384x216; lower = more wobble.
uniform vec2 snap = vec2(160.0, 90.0);

void vertex() {
	UV = UV * uv_scale;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (snap.x > 0.0 && clip.w > 0.0001) {
		vec3 ndc = clip.xyz / clip.w;
		ndc.xy = round(ndc.xy * snap) / snap;
		clip.xyz = ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_tex) {
		c *= texture(tex, UV).rgb;
	}
	if (use_vcol) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	EMISSION = emission.rgb;
}
