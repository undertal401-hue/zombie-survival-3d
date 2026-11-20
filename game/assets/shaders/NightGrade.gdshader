shader_type canvas_item;
render_mode blend_mix, unshaded;

// ============================================================================
// NIGHT GRADE - viñeta + grano + tinte frío para la noche (R1)
// ============================================================================
// Capa a pantalla completa (CanvasLayer) que se apoya sobre el mundo y DEBAJO
// del HUD. `night_amount` (0..1) lo gobierna SolarLighting.gd: 0 de día,
// 1 de noche. De día el shader es completamente transparente (no se nota).
//
// No sustituye a la iluminación: la oscuridad REAL la pone el CanvasModulate
// (multiplicador de color) y el faro (PointLight2D con sombras). Esto es la
// capa de "acabado": viñeta que cierra el encuadre, grano que rompe el
// banding de los degradados planos y un empujón frío que unifica la escena.
// ============================================================================

uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.85;
uniform float vignette_softness : hint_range(0.05, 1.0) = 0.42;
uniform float grain_strength : hint_range(0.0, 0.20) = 0.045;
uniform float grain_speed : hint_range(0.0, 120.0) = 26.0;
uniform vec4 night_tint : source_color = vec4(0.06, 0.09, 0.17, 1.0);

float hash21(vec2 p) {
	// Ruido determinista barato: suficiente para grano de película.
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	// Viñeta radial: 0 en el centro, 1 en las esquinas.
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 1.42;
	float vignette = smoothstep(vignette_softness, 1.0, dist);

	// Grano animado: cambia con el tiempo, así que no hace banding fijo.
	float noise = hash21(UV * vec2(1920.0, 1080.0)
			+ vec2(TIME * grain_speed, TIME * grain_speed * 0.73));
	float grain = (noise - 0.5) * grain_strength * night_amount;

	vec3 tint = night_tint.rgb * (1.0 + grain * 2.0);
	// `night_amount` se aplica UNA sola vez, al final: si también entra en la
	// viñeta, el efecto quedaría al cuadrado (0.55^2 en vez de 0.55).
	float alpha = clamp(vignette * vignette_strength
			+ abs(grain) * 0.6, 0.0, 1.0);

	// De día: nada. Sin esto el overlay tiñería la escena entera.
	COLOR = vec4(tint, alpha * night_amount);
}
