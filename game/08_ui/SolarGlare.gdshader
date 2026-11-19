shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glare_color : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform float glare_intensity : hint_range(0.0, 1.0) = 0.08;
uniform float glare_radius : hint_range(0.0, 1.0) = 0.75;
uniform float glare_falloff : hint_range(0.5, 5.0) = 2.2;
uniform vec2 sun_screen_pos = vec2(0.5, 0.3);

void fragment() {
	// Vector desde posición del sol a pixel actual (en UV 0-1)
	vec2 to_sun = sun_screen_pos - UV;
	// Corregir aspect ratio para que el resplandor sea circular
	vec2 aspect_corrected = to_sun * vec2(1.0, 1.0);
	float dist = length(aspect_corrected);

	// Resplandor radial suave con smoothstep
	float glow = 1.0 - smoothstep(0.0, glare_radius, dist);
	glow = pow(glow, glare_falloff) * glare_intensity;

	COLOR = glare_color * glow;
}