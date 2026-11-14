shader_type spatial
render_mode unshaded, cull_disabled, blend_mix

uniform sampler2D albedo_texture : hint_albedo;
uniform float fade_speed = 0.08;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * vec3(0.42, 0.02, 0.02);
	ALPHA = tex.a * max(0.0, 1.0 - TIME * fade_speed);
	if (ALPHA <= 0.01) discard;
}