shader_type canvas_item;

uniform float speed : hint_range(0.1, 5.0) = 1.2;
uniform float strength : hint_range(0.0, 1.0) = 0.15;
uniform float detail : hint_range(0.1, 10.0) = 3.0;
uniform float sway_width : hint_range(1.0, 200.0) = 50.0;

void vertex() {
	// UV.y が 0.0（先端）に近いほど揺れ幅を大きく、1.0（根元）に近いほど揺れないように制御
	float sway = sin(TIME * speed + VERTEX.y * detail) * strength * pow(1.0 - UV.y, 1.5);
	VERTEX.x += sway * sway_width;
}
