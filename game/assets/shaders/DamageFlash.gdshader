shader_type canvas_item;
render_mode unshaded;

// Flash de daño a pantalla completa. No muestrea TEXTURE: se aplica sobre un
// ColorRect y la intensidad la controla HUD.gd desde el uniform.
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(0.75, 0.0, 0.0, 1.0);

void fragment() {
	COLOR = vec4(flash_color.rgb, flash_color.a * damage_flash);
}
