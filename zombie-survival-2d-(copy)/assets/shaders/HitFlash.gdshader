shader_type canvas_item;

uniform float hit_flash_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Flash blanco aditivo
	float flash = hit_flash_progress;
	vec3 flash_rgb = flash_color.rgb * flash;
	
	// Aplicar flash
	COLOR = vec4(tex_color.rgb + flash_rgb, tex_color.a);
	
	// Si el alpha original es 0, no dibujar
	if (tex_color.a == 0.0) {
		discard;
	}
}