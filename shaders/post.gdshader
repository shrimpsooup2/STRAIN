// Full-screen retro pass: 15-bit colour with ordered dither, stage-driven "greyout"
// (everything but green drains), and a 1px tremor.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float levels = 31.0;      // per-channel steps (31 = 5-bit, DS-era)
uniform float dither = 1.0;       // 0..1 ordered-dither strength
uniform float grey = 0.0;         // 0..1 desaturate non-green pixels
uniform float tremor = 0.0;       // 0..1 chance-ish of a 1px horizontal shake
uniform vec2 px = vec2(0.0026041667, 0.0046296296);

const float BAYER[16] = {
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
};

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	if (tremor > 0.0) {
		float t = floor(TIME * 12.0);
		float h = hash(t);
		if (h < tremor * 0.5) {
			uv.x += (hash(t + 3.1) < 0.5 ? -1.0 : 1.0) * px.x;
		}
	}
	vec3 c = texture(screen_tex, uv).rgb;

	if (grey > 0.0) {
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		float greenness = clamp((c.g - max(c.r, c.b)) * 4.0, 0.0, 1.0);
		c = mix(c, vec3(l), grey * (1.0 - greenness));
	}

	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	float b = (BAYER[p.y * 4 + p.x] / 16.0 - 0.5) * dither;
	c = floor(c * levels + 0.5 + b) / levels;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
