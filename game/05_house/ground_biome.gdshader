shader_type canvas_item;

// =============================================================================
// BASE CONTINUA DEL SUELO
// =============================================================================
// El TileMap solo aporta cobertura: este shader pinta el color del terreno en
// funcion de la posicion de mundo, con ruido suave de varias escalas.
//
// Por que un shader y no tiles de color:
//   - Elegir el material por celda de 32 px produce bordes en escalera y
//     "parches" rectangulares (el bug visual reportado como bloques).
//   - Aqui el borde de bioma ondula con ruido y se mezcla en ~3 celdas, y las
//     manchas de tono son organicas, sin rejilla.
//
// Los colores NO son inventados: GroundTileMapV2 los calcula como la media
// opaca de columnas reales del atlas de Lumina y los pasa como uniformes.
// =============================================================================

uniform vec4 plains_light : source_color = vec4(0.4941, 0.6314, 0.3608, 1.0);
uniform vec4 plains_dark : source_color = vec4(0.3451, 0.5059, 0.3569, 1.0);
uniform vec4 urban_light : source_color = vec4(0.7719, 0.7453, 0.5834, 1.0);
uniform vec4 urban_dark : source_color = vec4(0.5053, 0.5659, 0.5799, 1.0);
uniform vec4 forest_light : source_color = vec4(0.3650, 0.5220, 0.3595, 1.0);
uniform vec4 forest_dark : source_color = vec4(0.2151, 0.3799, 0.3067, 1.0);

// Mitades de los biomas en pixeles de mundo (iguales que GroundTileMapV2).
uniform vec2 urban_half = vec2(2400.0, 1500.0);
uniform vec2 plains_half = vec2(3000.0, 2000.0);
// Ancho de la franja de mezcla del borde de bioma.
uniform float edge_softness = 190.0;
// Amplitud del ruido que ondula el borde (evita lineas rectas).
uniform float edge_wobble = 300.0;
// Ganancia global del color (1.0 = colores del atlas).
uniform float gain = 1.0;

varying vec2 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += vnoise(p) * amplitude;
		p = p * 2.03 + vec2(17.0, 31.0);
		amplitude *= 0.5;
	}
	return value / 0.875;
}

// Distancia rectangular con borde ondulado: negativa dentro, positiva fuera.
float box_distance(vec2 p, vec2 half_size, float wobble) {
	float d = max(abs(p.x) - half_size.x, abs(p.y) - half_size.y);
	return d + (fbm(p * 0.0021 + vec2(9.3, 4.7)) - 0.5) * wobble;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = world_pos;

	// Peso de cada bioma con transicion suave.
	float urban_weight = 1.0 - smoothstep(-edge_softness * 0.5, edge_softness * 0.5,
		box_distance(p, urban_half, edge_wobble));
	float plains_weight = 1.0 - smoothstep(-edge_softness * 0.5, edge_softness * 0.5,
		box_distance(p, plains_half, edge_wobble * 1.15));

	// Manchas organicas de tono (baja frecuencia) y grano fino.
	float patch = fbm(p * 0.0032 + vec2(41.0, 17.0));
	float grain = fbm(p * 0.085 + vec2(5.0, 91.0));
	float detail = 0.96 + 0.08 * grain;

	vec3 plains = mix(plains_dark.rgb, plains_light.rgb, smoothstep(0.28, 0.74, patch)) * detail;
	vec3 forest = mix(forest_dark.rgb, forest_light.rgb, smoothstep(0.32, 0.80, patch)) * detail;
	vec3 urban = mix(urban_dark.rgb, urban_light.rgb, smoothstep(0.35, 0.72, patch)) * detail;

	vec3 color = mix(forest, plains, plains_weight);
	color = mix(color, urban, urban_weight);

	COLOR = vec4(clamp(color * gain, 0.0, 1.0), 1.0);
}
