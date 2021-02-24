shader_type spatial;
render_mode unshaded, cull_disabled;

const float MESH_DEPTH = 0.05;
const float INV_MESH_DEPTH = 1.0 / MESH_DEPTH;

uniform vec4 albedo : hint_color;
uniform sampler2D portal_texture : hint_albedo;

varying float front;
varying float camera_behind;
varying float camera_by_portal;

void vertex() {
	// Automatically calculate required thickness of mesh to prevent near clipping issues.
	vec4 near_point = INV_PROJECTION_MATRIX * vec4(-1, -1, -1, 1);
	near_point /= near_point.w;
	float thickness = length(near_point.xyz);
	
	vec3 local_camera = (inverse(WORLD_MATRIX) * CAMERA_MATRIX[3]).xyz;
	camera_by_portal = float(clamp(local_camera.xy, -0.5, 0.5) == local_camera.xy);
	camera_behind = local_camera.z;
	
	VERTEX.z -= MESH_DEPTH * 0.5;
	VERTEX.z *= 0.5;
	front = -VERTEX.z / MESH_DEPTH;
	
	VERTEX.z *= INV_MESH_DEPTH * thickness * 2.0;
}

void fragment() {
	vec4 portal = texture(portal_texture, SCREEN_UV);
	
	if (camera_behind < 0.0 || (front != 0.0 && !bool(camera_by_portal))) {
		discard;
	}
	ALBEDO = portal.rgb;
}
