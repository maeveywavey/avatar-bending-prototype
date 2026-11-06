shader_type spatial;
// White placeholder surface that darkens and turns glossy where water has reached it.
// The wet region grows outward from wet_center (object space) as wet_radius increases.

uniform vec3 base_color : source_color = vec3(0.93, 0.92, 0.90);
uniform vec3 wet_color : source_color = vec3(0.50, 0.54, 0.60);
uniform vec3 wet_center = vec3(0.0);
uniform float wet_radius = 0.0;
uniform float wet_all = 0.0;

varying vec3 lp;

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

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float n = vnoise(lp * 9.0) * 0.6 + vnoise(lp * 23.0) * 0.4;
	float d = distance(lp, wet_center) + (n - 0.5) * 0.3;
	float w = wet_radius > 0.001 ? 1.0 - smoothstep(wet_radius - 0.06, wet_radius, d) : 0.0;
	w = max(w, wet_all);
	ALBEDO = mix(base_color, wet_color, w);
	ROUGHNESS = mix(0.9, 0.1, w);
	SPECULAR = mix(0.3, 0.8, w);
}
