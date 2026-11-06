shader_type spatial;
// Water surface. Tube mode: UV.x = metres along the stream, UV.y = angle round the tube (radians),
// COLOR.r = foam/aeration mask. World mode: noise is taken from world position (barrel surface).

uniform vec3 shallow_color : source_color = vec3(0.30, 0.72, 0.95);
uniform vec3 deep_color : source_color = vec3(0.0, 0.12, 0.32);
uniform float flow_speed = 1.8;
uniform float noise_scale = 9.0;
uniform float ripple_strength = 0.5;
uniform float refraction_strength = 0.06;
uniform float tint_amount = 0.8;
uniform bool world_noise = false;
uniform bool film = false;       // a sheet over an object: noise in object space, running downward
uniform float alpha = 1.0;       // multiplied by COLOR.a (film coverage)
uniform float fall_speed = 0.9;  // film mode: how fast the pattern runs downhill
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

varying vec3 wpos;
varying vec3 lpos;
varying vec3 wdown;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
				   mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				   mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(11.7, 5.3, 8.1);
		a *= 0.5;
	}
	return s;
}

vec3 field_pos(vec2 uv) {
	if (film) {
		return lpos * 7.0 - wdown * TIME * fall_speed;
	}
	if (world_noise) {
		return vec3(wpos.x * 3.0, TIME * 0.35, wpos.z * 3.0);
	}
	return vec3(uv.x * noise_scale - TIME * flow_speed, cos(uv.y) * 1.3, sin(uv.y) * 1.3);
}

// Parting (the stream's surface only): a hollow ahead of the bender (part_a, the bender's feet; part_dir,
// the aim), its centre part_c ahead, semi-axes part_ra along and part_rb across, a superellipse (exponent
// part_n_far ahead of the centre, part_n_near round the bender: 2 an ellipse, higher squarer); its walls
// round up over part_wall (in units of the shape) into ridges of the water pushed aside.
// Pond.part_shape() is the same function on the CPU (keep them matching); Pond sets all of these.
uniform bool parting = false;
uniform vec3 part_a = vec3(0.0);
uniform vec2 part_dir = vec2(0.0, 1.0);
uniform float part_open = 0.0;
uniform float part_c = 5.0;
uniform float part_ra = 7.0;
uniform float part_rb = 2.2;
uniform float part_n_near = 2.0;
uniform float part_n_far = 3.0;
uniform float part_wall = 0.4;
uniform float part_drop = 2.2;
uniform float part_ridge = 0.9;

float part_h(vec2 xz) {
	vec2 d = xz - part_a.xz;
	float a = dot(d, part_dir) - part_c;
	float c = dot(d, vec2(-part_dir.y, part_dir.x));
	float n = a < 0.0 ? part_n_near : part_n_far;
	float r = pow(pow(abs(a) / part_ra, n) + pow(abs(c) / part_rb, n), 1.0 / n);
	float w = smoothstep(1.0, 1.0 + part_wall, r);
	float ridge = w * exp(-max(r - 1.0 - part_wall, 0.0) * part_rb / 1.8);
	return part_open * (-part_drop * (1.0 - w) + part_ridge * ridge);
}

void vertex() {
	if (parting && part_open > 0.001) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float h = part_h(wp.xz);
		float e = 0.15;
		float hx = part_h(wp.xz + vec2(e, 0.0));
		float hz = part_h(wp.xz + vec2(0.0, e));
		VERTEX.y += h;
		NORMAL = normalize(vec3(-(hx - h) / e, 1.0, -(hz - h) / e));
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
	// world "down" in object space, so a film's ripples run downhill however the object turns
	wdown = normalize((inverse(MODEL_MATRIX) * vec4(0.0, -1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec3 p = field_pos(UV);
	float e = 0.06;
	float h = fbm(p);
	float hx = fbm(p + vec3(e, 0, 0));
	float hy = fbm(p + vec3(0, e, 0));
	float hz = fbm(p + vec3(0, 0, e));
	vec3 g = vec3(hx - h, hy - h, hz - h) / e;
	vec2 g2 = world_noise ? g.xz : g.xy;
	NORMAL_MAP = vec3(0.5 + g2.x * ripple_strength * 0.35, 0.5 + g2.y * ripple_strength * 0.35, 1.0);
	NORMAL_MAP_DEPTH = 1.0;

	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	vec2 off = NORMAL.xy * refraction_strength * (0.3 + 0.7 * ndv);
	vec3 refr = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	vec3 body = mix(shallow_color, deep_color, pow(ndv, 0.8));
	float tint = clamp(tint_amount * (0.55 + 0.6 * ndv), 0.0, 1.0);
	vec3 col = mix(refr, body, tint);

	// elongated bright streaks that travel with the flow
	float streak = fbm(p * vec3(0.45, 2.0, 2.0) + vec3(3.0, 0.0, 0.0));
	float st = smoothstep(0.58, 0.82, streak) * (0.25 + 0.75 * ndv);
	float foam = clamp(COLOR.r, 0.0, 1.0) * smoothstep(0.35, 0.75, h + COLOR.r * 0.25);
	col += vec3(st * 0.35) + vec3(foam * 0.8);

	ALBEDO = vec3(0.0);
	EMISSION = col * (1.0 - 0.5 * fres);
	ROUGHNESS = 0.04 + foam * 0.5;
	SPECULAR = 0.6;
	ALPHA = alpha * COLOR.a;
}
