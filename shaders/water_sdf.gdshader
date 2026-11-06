shader_type spatial;
// Water as one implicit surface, ray-marched per pixel (WaterSDF sets it up each frame). The shape is a set
// of round cones (two end spheres, a radius at each) in world space, optionally flattened along an axis.
// They are joined with a smooth minimum, so where two meet the surface rounds into a fillet the way liquid
// does: one continuous body, no seams, no parts clipping through each other.
// Drawn on the back faces of a box round the shape, with the depth test off: the ray starts at the box (or
// the camera, if it is inside), stops at whatever opaque thing is behind (a body, the ground) or at
// floor_y (the surface of a stream the water stands in, which is transparent and not in the depth
// buffer), and the water is coloured by how far the ray travels through it: clear where thin, deep where
// thick. Ripples are taken from position, so they never stretch as the shape changes.
render_mode blend_mix, cull_front, depth_test_disabled, depth_draw_never, shadows_disabled;

uniform vec4 seg_a[64];          // xyz: one end (world), w: its radius
uniform vec4 seg_b[64];          // the other end
uniform vec4 seg_c[64];          // xyz: an axis to flatten along (unit), w: the factor (1: round)
uniform int seg_count = 0;
uniform float blend_k = 0.15;    // how wide the joins round over (m)
uniform vec3 box_min;
uniform vec3 box_max;
uniform float floor_y = -100000.0;
uniform vec3 origin;             // waves and ripples are fixed to this point (the bender, the column...)
uniform vec3 drift = vec3(0.0);  // m/s the ripple pattern moves (falling water runs down)
uniform float wave_amp = 0.006;  // the light wave across the surface (m)
uniform float foam = 0.0;        // 0..1 white water

uniform vec3 shallow_color : source_color = vec3(0.30, 0.72, 0.95);
uniform vec3 deep_color : source_color = vec3(0.0, 0.14, 0.34);
uniform float absorb = 2.4;      // per metre of water the ray passes through
uniform float tint_amount = 0.75;
uniform float refraction_strength = 0.05;
uniform float ripple_strength = 0.35;
uniform float ripple_scale = 7.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

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
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(11.7, 5.3, 8.1);
		a *= 0.5;
	}
	return s;
}

// distance to a cone between two spheres, rounded at both ends (Inigo Quilez)
float sd_round_cone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
	vec3 ba = b - a;
	float l2 = dot(ba, ba);
	if (l2 < 0.000001) {
		return length(p - a) - max(r1, r2);
	}
	float rr = r1 - r2;
	float a2 = l2 - rr * rr;
	if (a2 <= 0.0) {
		// one sphere holds the other
		return min(length(p - a) - r1, length(p - b) - r2);
	}
	float il2 = 1.0 / l2;
	vec3 pa = p - a;
	float y = dot(pa, ba);
	float z = y - l2;
	vec3 xv = pa * l2 - ba * y;
	float x2 = dot(xv, xv);
	float y2 = y * y * l2;
	float z2 = z * z * l2;
	float k = sign(rr) * rr * rr * x2;
	if (sign(z) * a2 * z2 > k) {
		return sqrt(x2 + z2) * il2 - r2;
	}
	if (sign(y) * a2 * y2 < k) {
		return sqrt(x2 + y2) * il2 - r1;
	}
	return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}

float smin(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

// one piece, flattened along its axis by its factor (the ends stay where they are)
float sd_piece(vec3 p, int i) {
	vec3 a = seg_a[i].xyz;
	vec3 b = seg_b[i].xyz;
	float s = seg_c[i].w;
	if (s >= 0.999) {
		return sd_round_cone(p, a, b, seg_a[i].w, seg_b[i].w);
	}
	vec3 ax = seg_c[i].xyz;
	float st = 1.0 / max(s, 0.05) - 1.0;
	vec3 ps = p + ax * dot(p - a, ax) * st;
	vec3 bs = b + ax * dot(b - a, ax) * st;
	return sd_round_cone(ps, a, bs, seg_a[i].w, seg_b[i].w) * s;
}

float map(vec3 p, float tm) {
	float k = max(blend_k, 0.001);
	float d = 1e9;
	for (int i = 0; i < seg_count; i++) {
		// a cheap bound first: pieces too far away to matter are skipped
		vec3 a = seg_a[i].xyz;
		vec3 b = seg_b[i].xyz;
		float br = length(b - a) * 0.5 + max(seg_a[i].w, seg_b[i].w);
		if (length(p - (a + b) * 0.5) - br > d + k) {
			continue;
		}
		d = smin(d, sd_piece(p, i), k);
	}
	// a light, slow wave across the surface
	vec3 q = p - origin - drift * tm;
	d += wave_amp * (sin(q.x * 9.0 + tm * 1.3) * sin(q.z * 8.0 - tm * 1.1)
			+ 0.6 * sin(q.y * 11.0 + q.x * 4.0 + tm * 0.9));
	return d;
}

vec3 sdf_normal(vec3 p, float tm) {
	vec2 e = vec2(0.002, -0.002);
	return normalize(e.xyy * map(p + e.xyy, tm) + e.yyx * map(p + e.yyx, tm)
			+ e.yxy * map(p + e.yxy, tm) + e.xxx * map(p + e.xxx, tm));
}

void fragment() {
	float tm = TIME;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize(wp - cam);

	// where the ray is inside the box
	vec3 sr = vec3(rd.x >= 0.0 ? 1.0 : -1.0, rd.y >= 0.0 ? 1.0 : -1.0, rd.z >= 0.0 ? 1.0 : -1.0);
	vec3 inv = 1.0 / (rd + sr * 0.000001);
	vec3 ta = (box_min - cam) * inv;
	vec3 tb = (box_max - cam) * inv;
	vec3 t_lo = min(ta, tb);
	vec3 t_hi = max(ta, tb);
	float tn = max(max(t_lo.x, t_lo.y), max(t_lo.z, 0.0));
	float tf = min(min(t_hi.x, t_hi.y), t_hi.z);

	// the opaque scene behind: the ray stops there
	float zd = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zd, 1.0);
	sv.xyz /= sv.w;
	float t_end = min(tf, length(sv.xyz));
	// and at the stream's surface, from either side
	if (abs(rd.y) > 0.00001) {
		float tfl = (floor_y - cam.y) / rd.y;
		if (cam.y >= floor_y && rd.y < 0.0) {
			t_end = min(t_end, tfl);
		} else if (cam.y < floor_y) {
			if (rd.y > 0.0) {
				tn = max(tn, tfl);
			} else {
				discard;
			}
		}
	}
	if (tn >= t_end) {
		discard;
	}

	float t = tn;
	bool hit = false;
	// cost: each step checks every piece near the ray, for every pixel of the box; steps are capped, and
	// the surface is accepted a little sooner the farther away it is
	for (int i = 0; i < 56; i++) {
		float d = map(cam + rd * t, tm);
		if (d < 0.002 * (1.0 + t * 0.5)) {
			hit = true;
			break;
		}
		t += max(d * 0.9, 0.004);
		if (t > t_end) {
			break;
		}
	}
	if (!hit || t > t_end) {
		discard;
	}
	vec3 p = cam + rd * t;

	// how far the ray goes through the water before leaving it or meeting something opaque
	float t2 = t + 0.01;
	for (int i = 0; i < 10; i++) {
		if (t2 > t_end) {
			break;
		}
		float d = map(cam + rd * t2, tm);
		if (d > 0.0) {
			break;
		}
		t2 += max(-d, 0.03);
	}
	float thick = max(min(t2, t_end) - t, 0.0);

	// the surface normal, with fine ripples
	vec3 n = sdf_normal(p, tm);
	vec3 q = (p - origin - drift * tm) * ripple_scale + vec3(0.0, tm * 0.12, tm * 0.05);
	float e = 0.06;
	float h = fbm(q);
	vec3 g = vec3(fbm(q + vec3(e, 0, 0)) - h, fbm(q + vec3(0, e, 0)) - h, fbm(q + vec3(0, 0, e)) - h) / e;
	n = normalize(n - (g - n * dot(g, n)) * ripple_strength * 0.12);
	vec3 nv = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	NORMAL = nv;

	float ndv = clamp(dot(nv, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	float depthf = 1.0 - exp(-thick * absorb);
	// what is behind, bent through the surface: more where the water is thicker
	vec2 off = nv.xy * refraction_strength * (0.4 + 1.6 * depthf);
	vec3 refr = textureLod(screen_tex, SCREEN_UV - off, 0.0).rgb;
	refr *= mix(vec3(1.0), shallow_color * 1.25, depthf * 0.6);
	vec3 body = mix(shallow_color, deep_color, clamp(depthf * 1.2, 0.0, 1.0));
	vec3 col = mix(refr, body, clamp(0.1 + tint_amount * depthf, 0.0, 1.0));

	// faint bright streaks in the body of the water, white water, and the sky caught at grazing angles
	float streak = vnoise(q * vec3(0.5, 1.6, 0.5) + vec3(3.0, 0.0, 0.0));
	col += vec3(smoothstep(0.6, 0.85, streak) * 0.18 * (0.3 + 0.7 * ndv));
	col = mix(col, vec3(0.92, 0.97, 1.0), foam * smoothstep(0.35, 0.75, h + foam * 0.2));
	col += vec3(0.55, 0.7, 0.85) * fres * 0.3;

	ALBEDO = vec3(0.0);
	EMISSION = col * (1.0 - 0.4 * fres);
	ROUGHNESS = 0.05 + foam * 0.4;
	SPECULAR = 0.6;
	// the very rim (a few mm of water) fades, so the outline is soft
	ALPHA = clamp(thick / 0.006, 0.0, 1.0);
}
