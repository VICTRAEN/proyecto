shader_type canvas_item;

// ILUMINACION DE PERSONAJE. Se aplica al ARTE ORIGINAL (nunca se modifica el PNG):
//   - cel-shading suave: la luminosidad se cuantiza un poco, sin cambiar el tono
//   - gradacion de color: sombras hacia violeta, luces hacia calido
//   - luz de contorno (rim light): un filo luminoso en el borde que mira a la luz,
//     del color del tipo del personaje
// Cuesta tres lecturas de textura por pixel. Todos los parametros son opcionales.

uniform float cel_strength : hint_range(0.0, 1.0) = 0.20;
uniform float cel_levels : hint_range(2.0, 12.0) = 5.0;
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.16;
uniform float warm_strength : hint_range(0.0, 1.0) = 0.08;
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.50, 1.0, 1.0);
uniform vec4 warm_tint : source_color = vec4(1.0, 0.92, 0.80, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.85;
uniform vec4 rim_color : source_color = vec4(1.0, 0.86, 0.95, 1.0);
// Ancho del filo en TEXELES (el codigo lo ajusta para que se vea de ~3 px).
uniform float rim_px : hint_range(0.5, 60.0) = 3.0;
// Hacia donde esta la luz (arriba-izquierda en pantalla).
uniform vec2 light_dir = vec2(-0.55, -0.83);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = tex.rgb;
	float a = tex.a;
	float l = dot(col, vec3(0.299, 0.587, 0.114));

	float quant = floor(l * cel_levels + 0.5) / cel_levels;
	float target = mix(l, quant, cel_strength);
	col *= target / max(l, 0.03);

	float shade = 1.0 - smoothstep(0.0, 0.55, l);
	col = mix(col, col * shadow_tint.rgb * 1.45, shade * shadow_tint_strength);
	col = mix(col, col * warm_tint.rgb, smoothstep(0.55, 1.0, l) * warm_strength);

	vec2 step_uv = TEXTURE_PIXEL_SIZE * rim_px * normalize(light_dir);
	float outside = 1.0 - 0.5 * (texture(TEXTURE, UV + step_uv).a + texture(TEXTURE, UV + step_uv * 2.2).a);
	float rim = clamp(a * outside, 0.0, 1.0);
	col = 1.0 - (1.0 - col) * (1.0 - rim_color.rgb * rim * rim_strength);

	COLOR = vec4(clamp(col, 0.0, 1.0), a) * COLOR;
}
