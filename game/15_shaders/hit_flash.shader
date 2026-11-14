shader_type canvas_item
render_mode blend_add

uniform sampler2D screen_texture : hint_screen_texture;
uniform float flash_amount = 0.0;
uniform float flash_speed = 15.0;

void fragment() {
	vec4 color = texture(screen_texture, SCREEN_UV);
	float flash = sin(TIME * flash_speed) * 0.5 + 0.5;
	color.rgb += vec3(1.0, 0.2, 0.1) * flash_amount * flash;
	COLOR = color;
}