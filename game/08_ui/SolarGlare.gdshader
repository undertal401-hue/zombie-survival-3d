shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glare_color : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform float glare_intensity : hint_range(0.0, 1.0) = 0.08;
uniform float glare_radius : hint_range(0.0, 1.0) = 0.75;
uniform float glare_falloff : hint_range(0.5, 5.0) = 2.2;
uniform vec2 sun_screen_pos = vec2(0.5, 0.3);

void fragment() {
	// Vector desde el pixel actual hasta la posición del sol (en UV 0-1).
	vec2 to_sun = sun_screen_pos - UV;
	// Corregir aspecto del viewport para que el resplandor sea circular en
	// pantallas no cuadradas. SCREEN_PIXEL_SIZE permite hacerlo solo desde el
	// shader, sin uniforms extra ni cambios en SolarLighting.gd.
	float aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.000001);
	to_sun.x *= aspect;
	float dist = length(to_sun);

	// Resplandor radial suave con smoothstep
	float glow = 1.0 - smoothstep(0.0, glare_radius, dist);
	glow = pow(glow, glare_falloff) * glare_intensity;

	COLOR = glare_color * glow;
}