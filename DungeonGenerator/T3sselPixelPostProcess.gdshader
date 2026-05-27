shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform bool effect_enabled = true;
uniform float mix_amount : hint_range(0.0, 1.0) = 1.0;
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;
uniform float color_steps : hint_range(2.0, 16.0, 1.0) = 7.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.0;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.18;
uniform float saturation : hint_range(0.0, 2.0) = 0.9;
uniform float contrast : hint_range(0.0, 2.0) = 1.08;
uniform vec4 shadow_tint : source_color = vec4(0.05, 0.08, 0.12, 1.0);
uniform vec4 highlight_tint : source_color = vec4(0.86, 0.95, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.16;

float luma(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

float bayer4(vec2 pixel) {
	vec2 p = mod(floor(pixel), 4.0);
	float x = p.x;
	float y = p.y;
	float index = x + y * 4.0;
	float value = 0.0;

	if (index < 0.5) {
		value = 0.0;
	} else if (index < 1.5) {
		value = 8.0;
	} else if (index < 2.5) {
		value = 2.0;
	} else if (index < 3.5) {
		value = 10.0;
	} else if (index < 4.5) {
		value = 12.0;
	} else if (index < 5.5) {
		value = 4.0;
	} else if (index < 6.5) {
		value = 14.0;
	} else if (index < 7.5) {
		value = 6.0;
	} else if (index < 8.5) {
		value = 3.0;
	} else if (index < 9.5) {
		value = 11.0;
	} else if (index < 10.5) {
		value = 1.0;
	} else if (index < 11.5) {
		value = 9.0;
	} else if (index < 12.5) {
		value = 15.0;
	} else if (index < 13.5) {
		value = 7.0;
	} else if (index < 14.5) {
		value = 13.0;
	} else {
		value = 5.0;
	}

	return (value + 0.5) / 16.0;
}

vec3 apply_contrast_saturation(vec3 color) {
	color = (color - 0.5) * contrast + 0.5;
	float gray = luma(color);
	return mix(vec3(gray), color, saturation);
}

void fragment() {
	vec4 source = texture(screen_texture, SCREEN_UV);

	if (effect_enabled) {
		vec2 screen_size = vec2(textureSize(screen_texture, 0));
		vec2 block_size = vec2(
			max(pixel_size, 1.0) / max(screen_size.x, 1.0),
			max(pixel_size, 1.0) / max(screen_size.y, 1.0)
		);
		vec2 block_uv = (floor(SCREEN_UV / block_size) + vec2(0.5)) * block_size;
		vec3 color = texture(screen_texture, block_uv).rgb;

		float center_luma = luma(color);
		float right_luma = luma(texture(screen_texture, block_uv + vec2(block_size.x, 0.0)).rgb);
		float left_luma = luma(texture(screen_texture, block_uv - vec2(block_size.x, 0.0)).rgb);
		float up_luma = luma(texture(screen_texture, block_uv + vec2(0.0, block_size.y)).rgb);
		float down_luma = luma(texture(screen_texture, block_uv - vec2(0.0, block_size.y)).rgb);
		float edge = abs(center_luma - right_luma)
			+ abs(center_luma - left_luma)
			+ abs(center_luma - up_luma)
			+ abs(center_luma - down_luma);

		color = apply_contrast_saturation(color);

		float quant_step = 1.0 / max(color_steps, 2.0);
		float dither = bayer4(FRAGCOORD.xy / max(pixel_size, 1.0)) - 0.5;
		vec3 dithered = clamp(color + dither * dither_strength * quant_step, 0.0, 1.0);
		vec3 quantized = floor(dithered * color_steps + 0.5) / color_steps;

		float tone = luma(quantized);
		vec3 tinted = mix(quantized, shadow_tint.rgb, (1.0 - tone) * tint_strength);
		tinted = mix(tinted, highlight_tint.rgb, tone * tint_strength * 0.55);

		float edge_mix = clamp(edge * 2.5, 0.0, 1.0) * edge_strength;
		vec3 edged = mix(tinted, tinted * 0.35, edge_mix);

		COLOR = vec4(mix(source.rgb, edged, mix_amount), source.a);
	} else {
		COLOR = source;
	}
}
