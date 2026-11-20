// Transparent unlit variant: glass, glows, motes, overlays.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform bool use_tex = false;
uniform float uv_scale = 1.0;
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
	vec4 c = albedo;
	if (use_tex) {
		c *= texture(tex, UV);
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
