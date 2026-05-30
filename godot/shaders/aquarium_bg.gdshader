shader_type canvas_item;

// 背景グラデーション色 (上部・下部)
uniform vec4 color_top : source_color = vec4(0.08, 0.35, 0.58, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.015, 0.09, 0.22, 1.0);

// Caustics (光の揺らぎ) の制御パラメータ
uniform float caustics_speed : hint_range(0.0, 5.0) = 0.5;
uniform float caustics_scale : hint_range(0.1, 10.0) = 3.0;
uniform float caustics_strength : hint_range(0.0, 1.0) = 0.28;
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
	// 波立つ水面の境界線を計算 (複数のサイン波を重ねて不規則な波を作る)
	float wave_y = 0.06 
		+ sin(UV.x * 25.0 + TIME * 1.2) * 0.003 
		+ cos(UV.x * 12.0 - TIME * 0.8) * 0.0015
		+ sin(UV.x * 4.0 + TIME * 0.3) * 0.005;
	
	vec4 bg;
	if (UV.y < wave_y) {
		// 水面上の外光レイヤー (上に向かってさらに白くグラデーション)
		float surf_glow = pow(1.0 - (UV.y / wave_y), 1.5);
		bg = mix(vec4(0.1, 0.5, 0.75, 1.0), vec4(0.7, 0.96, 1.0, 1.0), surf_glow);
	} else {
		// 水中レイヤー (水面境界から最下部までのグラデーション)
		float adjusted_y = (UV.y - wave_y) / (1.0 - wave_y);
		bg = mix(color_top, color_bottom, adjusted_y);
		
		// Caustics の計算
		vec2 uv = UV * caustics_scale;
		float t = TIME * caustics_speed;
		
		float wave1 = get_caustics_wave(uv, t);
		float wave2 = get_caustics_wave(uv * 1.7 + vec2(0.3, 0.7), t * 1.2) * 0.6;
		float final_wave = (wave1 + wave2) * caustics_strength;
		
		// 深度減衰 (水面境界に近いほど光が強く、下部ほど暗くなる)
		float depth_fade = pow(1.0 - adjusted_y, caustics_fade);
		
		// 背景色に加算
		bg.rgb += vec3(final_wave * depth_fade);
	}
	
	// 水面ラインのハイライトエフェクト (白波・発光ライン)
	float dist_to_wave = abs(UV.y - wave_y);
	float wave_edge = smoothstep(0.004, 0.0, dist_to_wave);
	bg.rgb = mix(bg.rgb, vec3(0.9, 0.98, 1.0), wave_edge * 0.7);
	
	COLOR = bg;
}
