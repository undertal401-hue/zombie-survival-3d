shader_type spatial
render_mode unshaded, cull_front, blend_mix

uniform vec3 outline_color = vec3(1.0, 0.8, 0.0);
uniform float outline_width = 0.04;
uniform float pulse_speed = 3.0;

void vertex() {
	VERTEX = VERTEX + NORMAL * (outline_width + sin(TIME * pulse_speed) * 0.005);
}

void fragment() {
	ALBEDO = outline_color;
	ALPHA = 0.8 + sin(TIME * pulse_speed) * 0.2;
}