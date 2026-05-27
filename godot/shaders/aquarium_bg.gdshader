shader_type canvas_item;

// 背景グラデーション色 (上部・下部)
uniform vec4 color_top : source_color = vec4(0.02, 0.12, 0.22, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.005, 0.03, 0.08, 1.0);

// Caustics (光の揺らぎ) の制御パラメータ
uniform float caustics_speed : hint_range(0.0, 5.0) = 0.5;
uniform float caustics_scale : hint_range(0.1, 10.0) = 2.0;
uniform float caustics_strength : hint_range(0.0, 1.0) = 0.18;
uniform float caustics_fade : hint_range(0.0, 2.0) = 1.2; // 水深が深くなるにつれて光が減衰する強さ

// 簡易擬似ノイズを生成する波の干渉関数
float get_caustics_wave(vec2 uv, float time) {
	// 複数の異なる周期と速度の波を干渉させる
	float w1 = sin(uv.x * 3.0 + time) * cos(uv.y * 3.0 - time);
	float w2 = sin(uv.y * 5.0 - time * 1.3) * cos(uv.x * 4.0 + time * 0.8);
	float w3 = sin((uv.x + uv.y) * 2.5 + time * 1.5);
	
	// 波を合成し、鋭い光の網目を作るために累乗(power)を適用
	float combined = (w1 + w2 + w3) / 3.0;
	combined = smoothstep(0.1, 0.9, combined);
	return pow(combined, 3.0); // 網目を目立たせる
}

void fragment() {
	// 縦方向のグラデーション背景
	vec4 bg = mix(color_top, color_bottom, UV.y);
	
	// Caustics の計算
	vec2 uv = UV * caustics_scale;
	float t = TIME * caustics_speed;
	
	// 異なるスケールで2つの網目を重ねて奥行きを出す
	float wave1 = get_caustics_wave(uv, t);
	float wave2 = get_caustics_wave(uv * 1.7 + vec2(0.3, 0.7), t * 1.2) * 0.6;
	float final_wave = (wave1 + wave2) * caustics_strength;
	
	// 深度減衰 (海面に近い上部ほど光が強く、下部ほど暗くなる)
	float depth_fade = pow(1.0 - UV.y, caustics_fade);
	
	// 背景色に加算
	bg.rgb += vec3(final_wave * depth_fade);
	
	COLOR = bg;
}
