shader_type canvas_item;

// 走査のステップ数。大きいほど判定の解像度（精度）が上がります。
const int STEPS = 50;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// すでに不透明（線画の部分、またはユーザーが塗った部分）なら、そのままの色を出力
	if (tex_color.a > 0.1) {
		COLOR = tex_color;
	} else {
		// 完全またはほぼ透明なピクセルの場合、上下左右の4方向に走査して黒線に囲まれているかチェックする
		bool hit_up = false;
		bool hit_down = false;
		bool hit_left = false;
		bool hit_right = false;
		
		// 1. 上方向の走査
		for (int i = 1; i <= STEPS; i++) {
			float offset = float(i) / float(STEPS) * UV.y;
			vec2 scan_uv = vec2(UV.x, UV.y - offset);
			if (textureLod(TEXTURE, scan_uv, 0.0).a > 0.5) {
				hit_up = true;
				break;
			}
		}
		
		// 2. 下方向の走査
		for (int i = 1; i <= STEPS; i++) {
			float offset = float(i) / float(STEPS) * (1.0 - UV.y);
			vec2 scan_uv = vec2(UV.x, UV.y + offset);
			if (textureLod(TEXTURE, scan_uv, 0.0).a > 0.5) {
				hit_down = true;
				break;
			}
		}
		
		// 3. 左方向の走査
		for (int i = 1; i <= STEPS; i++) {
			float offset = float(i) / float(STEPS) * UV.x;
			vec2 scan_uv = vec2(UV.x - offset, UV.y);
			if (textureLod(TEXTURE, scan_uv, 0.0).a > 0.5) {
				hit_left = true;
				break;
			}
		}
		
		// 4. 右方向の走査
		for (int i = 1; i <= STEPS; i++) {
			float offset = float(i) / float(STEPS) * (1.0 - UV.x);
			vec2 scan_uv = vec2(UV.x + offset, UV.y);
			if (textureLod(TEXTURE, scan_uv, 0.0).a > 0.5) {
				hit_right = true;
				break;
			}
		}
		
		// 4方向すべてで線（アルファ>0.5の不透明部分）に衝突した場合、内側（体内）とみなして白を塗る
		if (hit_up && hit_down && hit_left && hit_right) {
			COLOR = vec4(1.0, 1.0, 1.0, 1.0);
		} else {
			// いずれかの方向で外側に抜けられた場合は背景（透明）のままにする
			COLOR = tex_color;
		}
	}
}
