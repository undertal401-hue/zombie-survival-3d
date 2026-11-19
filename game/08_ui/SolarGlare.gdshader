shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glare_color : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform float glare_intensity : hint_range(0.0, 1.0) = 0.08;
uniform float glare_radius : hint_range(0.0, 1.0) = 0.75;
uniform float glare_falloff : hint_range(0.5, 5.0) = 2.2;
uniform vec2 sun_screen_pos = vec2(0.5, 0.3);
// ancho/alto del viewport, cableado desde SolarLighting.gd (default = cuadrado)
uniform float viewport_aspect = 1.0;

void fragment() {
	// Vector desde el pixel actual hasta la posición del sol (en UV 0-1).
	vec2 to_sun = sun_screen_pos - UV;
	// UV va 0-1 en ambos ejes: multiplicar X por ancho/alto lleva la
	// distancia a espacio de pantalla y hace circular el resplandor
	// aunque el viewport no sea cuadrado.
	vec2 d = to_sun;
	d.x *= viewport_aspect;
	float dist = length(d);

	// Resplandor radial suave con smoothstep
	float glow = 1.0 - smoothstep(0.0, glare_radius, dist);
	glow = pow(glow, glare_falloff) * glare_intensity;

	COLOR = glare_color * glow;
}