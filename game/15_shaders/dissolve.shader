shader_type spatial
render_mode cull_disabled, blend_mix

uniform sampler2D albedo : hint_albedo;
uniform sampler2D noise : hint_white;
uniform float dissolve_threshold = 0.0;
uniform vec3 edge_color = vec3(1.0, 0.4, 0.1);
uniform float edge_width = 0.02;

void fragment() {
	vec4 tex = texture(albedo, UV);
	float noise_val = texture(noise, UV * 4.0).r;
	
	float dissolve = noise_val - dissolve_threshold;
	
	if (dissolve < 0.0) discard;
	
	if (dissolve < edge_width) {
		float edge = 1.0 - dissolve / edge_width;
		ALBEDO = mix(tex.rgb, edge_color, edge);
		ALPHA = tex.a * edge;
	} else {
		ALBEDO = tex.rgb;
		ALPHA = tex.a;
	}
}