shader_type canvas_item;
// Behind the form wheel: the world blurred (a lower mip of the screen), greyed a little and darkened, so
// the wheel stands out. amount fades it in and out (0..1).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 6.0 * amount;
	float lod = 2.5 * amount;
	// a few offset taps on top of the mip smooth out its blockiness
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.4;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, px.y), lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y), lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y), lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, -px.y), lod).rgb * 0.15;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey), 0.35 * amount);
	c *= 1.0 - 0.5 * amount;
	COLOR = vec4(c, 1.0);
}
