shader_type canvas_item
render_mode blend_mix

uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D noise_texture;
uniform float infection_amount = 0.0;
uniform float vein_intensity = 1.0;
uniform float desaturation = 1.0;
uniform float time_speed = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 color = texture(screen_texture, uv);
	
	// Venas animadas
	vec2 noise_uv = uv * 8.0 + vec2(TIME * time_speed * 0.3, 0.0);
	float veins = texture(noise_texture, noise_uv).r;
	veins = smoothstep(0.45, 0.55, veins) * vein_intensity * infection_amount;
	
	// Desaturacion progresiva
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(color.rgb, vec3(gray), desaturation * infection_amount);
	
	// Tinte rojo infeccion
	color.rgb += vec3(0.35, 0.0, 0.0) * infection_amount * 0.5;
	color.rgb += vec3(0.5, 0.0, 0.0) * veins;
	
	COLOR = color;
}