tool
extends Spatial
class_name Portal, "portal.svg"

const _PORTAL_LIST = "__portals"
const _PORTAL_SCENE = "res://addons/silicon.3d.portals/portal.tscn"

export var link : NodePath
export var recursion_limit := 2

export var cull_bias := 0.5

export var portal_material: ShaderMaterial = preload("default_portal.material") setget set_portal_material
export var default_material: Material setget set_default_material

var main_view: Viewport

var sub_portals := []
var is_sub_portal := false
var original_portal: Portal

var clip_polygon := PoolVector2Array() # UNUSED

var active := true
var parent: Portal
var root: Portal

var last_frame_active := 0

onready var portal_link: Spatial = get_node_or_null(link)

onready var viewport: Viewport = $Viewport
onready var camera: Camera = $Viewport/Camera
onready var sender: Spatial = $Sender


func _enter_tree() -> void:
	if get_tree().edited_scene_root == self or (get_child_count() > 0 and get_child(0).name == "__PORTAL_TAG__"):
		return
	
	var nodes: Spatial = load(_PORTAL_SCENE).instance()
	for node in nodes.get_children():
		nodes.remove_child(node)
		add_child(node)
	nodes.queue_free()


func _ready() -> void:
	set_portal_material(portal_material)
	set_default_material(default_material)
	
	if Engine.editor_hint:
		return
	
	main_view = get_viewport()
	while not is_sub_portal and not main_view.own_world and main_view != get_tree().root:
		main_view = main_view.get_viewport()
	
	if not is_sub_portal:
		if main_view.has_meta(_PORTAL_LIST):
			main_view.get_meta(_PORTAL_LIST).append(self)
		else:
			main_view.set_meta(_PORTAL_LIST, [self])
			main_view.set_meta("__frames_drawn", -1)
			main_view.set_meta("__reserved_layers", [])
			main_view.set_meta("__reserved_layer_bits", [])


func _process(_delta: float) -> void:
	if get_tree().edited_scene_root == self:
		return
	
	_update_material()
	
	var main_cam := main_view.get_camera() if main_view else null
	var root_view = root.main_view if is_sub_portal else main_view
	if not Engine.editor_hint:
		if root_view.get_meta("__frames_drawn") != Engine.get_frames_drawn():
			root_view.set_meta("__frames_drawn", Engine.get_frames_drawn())
			root_view.set_meta("__reserved_layers", _get_reserved_layers())
			root_view.set_meta("__main_reserved_layer", root_view.get_meta("__reserved_layers").pop_back())
		
		if not is_sub_portal:
			$Surface.layers = root_view.get_meta("__main_reserved_layer")
			$Default.layers = root_view.get_meta("__main_reserved_layer")
	
	if not is_working():
		if viewport:
			viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
		_deactivate_portals(sub_portals)
		$Surface.visible = false
		$Default.visible = true
		last_frame_active += 1
		return
	else:
		if last_frame_active != -1:
			viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
		else:
			viewport.render_target_update_mode = Viewport.UPDATE_WHEN_VISIBLE
		$Surface.visible = true
		$Default.visible = false
		last_frame_active = -1
	
#	print(str(Engine.get_frames_drawn()) + ": " + _get_recursive_name())
#	if _get_recursive_name() == "PortalD/PortalD":
#		breakpoint
	
	viewport.size = root_view.size
	_update_camera(main_cam)
	
	var visible_portals := []
	var potential_portals: Array = root_view.get_meta(_PORTAL_LIST)
	potential_portals.sort_custom(PortalSort.new(main_cam.global_transform), "sort")
	var clipping_planes := camera.get_frustum() + [portal_link.get_plane()]
	for portal in potential_portals:
		if not portal.is_visible_in_tree():
			continue
		
		var points: PoolVector3Array = portal.get_polygon()
		for plane in clipping_planes:
			if len(points) == 0:
				break
			points = Geometry.clip_polygon(points, plane)
		
		clip_polygon.resize(0)
		for point in points:
			clip_polygon.append(camera.unproject_position(point))
		
		if not clip_polygon.empty() and Geometry.is_polygon_clockwise(clip_polygon):
			visible_portals.append(portal)
	
	var reserved_layer := 0
	if not root_view.get_meta("__reserved_layers").empty():
		reserved_layer = root_view.get_meta("__reserved_layers").pop_back()
	
	var available_sub_portals = sub_portals.duplicate()
	camera.cull_mask = main_cam.cull_mask & ~_get_reserved_layer_bits()
	camera.cull_mask |= reserved_layer
	for portal in visible_portals:
		var sub_portal: Portal = _get_sub_portal(available_sub_portals)
		if sub_portal:
			sub_portal.active = true
			sub_portal.root = root if root else self
			sub_portal.parent = self
			sub_portal.recursion_limit = recursion_limit - 1
			sub_portal.original_portal = portal
			sub_portal.name = portal.name
			sub_portal.transform = portal.global_transform
			sub_portal.portal_link = portal.portal_link
			sub_portal.cull_bias = portal.cull_bias
			sub_portal.portal_material = portal.portal_material
			sub_portal.default_material = portal.default_material
			sub_portal.get_node("Surface").layers = reserved_layer
			sub_portal.get_node("Default").layers = reserved_layer
	_deactivate_portals(available_sub_portals)


func _exit_tree() -> void:
	if Engine.editor_hint:
		return
	
	if not is_sub_portal:
		main_view.get_meta(_PORTAL_LIST).erase(self)


func teleport_transform(trans := Transform.IDENTITY) -> Transform:
	return portal_link.sender.global_transform.orthonormalized() * global_transform.orthonormalized().inverse() * trans


func set_portal_material(value: ShaderMaterial) -> void:
	if portal_material != value or portal_material.shader != value.shader:
		portal_material = value
		if has_node("Surface"):
			$Surface.material_override = portal_material.duplicate()
	
	if portal_material and has_node("Surface"):
		var view_tex := viewport.get_texture()
		$Surface.material_override.set_shader_param("portal_texture", view_tex)


func set_default_material(value: Material) -> void:
	default_material = value
	if has_node("Default"):
		$Default.material_override = default_material


func get_plane() -> Plane:
	return Plane(
		global_transform.origin,
		global_transform.origin + global_transform.basis.x,
		global_transform.origin + global_transform.basis.y
	)


func get_polygon() -> PoolVector3Array:
	var trans = global_transform
	return PoolVector3Array([
		trans.origin - trans.basis.x * 0.5 - trans.basis.y * 0.5,
		trans.origin + trans.basis.x * 0.5 - trans.basis.y * 0.5,
		trans.origin + trans.basis.x * 0.5 + trans.basis.y * 0.5,
		trans.origin - trans.basis.x * 0.5 + trans.basis.y * 0.5
	])


func is_working() -> bool:
	return is_visible_in_tree() and portal_link and active and main_view and recursion_limit != 0 and not Engine.editor_hint


func _get_recursive_name() -> String:
	var recursive_name := name
	if parent:
		recursive_name = parent._get_recursive_name() + "/" + recursive_name
	return recursive_name


func _get_sub_portal(available_portals: Array) -> Portal:
	var sub_portal
	if not available_portals.empty():
		sub_portal = available_portals.pop_front()
	else:
		sub_portal = load(_PORTAL_SCENE).instance()
		sub_portal.script = get_script()
		sub_portal.process_priority = process_priority + 1
		sub_portal.is_sub_portal = true
		viewport.add_child(sub_portal)
		sub_portals.append(sub_portal)
		sub_portal.call_deferred("_process", 0.0)
	
	return sub_portal


func _deactivate_portals(portals: Array) -> void:
	for portal in portals:
		portal.active = false


func _get_reserved_layers() -> Array:
	var array := []
	for layer in range(32, 0, -1):
		var setting := "layer_names/3d_render/layer_%d" % layer
		if ProjectSettings.has_setting(setting) and ProjectSettings.get_setting(setting) == "PORTAL_RESERVED":
			array.append(1 << (layer - 1))
	return array


func _get_reserved_layer_bits() -> int:
	var bits := 0
	for layer in _get_reserved_layers():
		bits |= layer
	return bits


func _update_material() -> void:
	var original_mat: ShaderMaterial = portal_material
	var material: ShaderMaterial = $Surface.material_override
	
	if not material or not original_mat:
		return
	
	var params := VisualServer.shader_get_param_list(material.shader.get_rid())
	for param in params:
		if param.name in ["portal_texture"]:
			continue
		material.set_shader_param(param.name, original_mat.get_shader_param(param.name))


func _update_camera(main_cam : Camera) -> void:
	var main_cam_pos := main_cam.global_transform.origin
	camera.global_transform = teleport_transform(main_cam.global_transform)
	
	var closest_dist_to_cam := -1.0
	var plane := get_plane()
	
	# Since we lack oblique near planes, calculate the nearest the near plane can be.
	var points := [Vector2.ZERO, Vector2(0, main_view.size.y), Vector2(main_view.size.x, 0), main_view.size]
	for i in points.size():
		var far := main_cam.project_position(points[i], main_cam.near)
		var intersect := plane.intersects_ray(main_cam_pos, far - main_cam_pos)
		if not intersect:
			continue
		
		intersect = to_local(intersect)
		intersect.x = clamp(intersect.x, -0.5, 0.5)
		intersect.y = clamp(intersect.y, -0.5, 0.5)
		intersect = to_global(intersect)
		
		if closest_dist_to_cam == -1:
			closest_dist_to_cam = -main_cam.to_local(intersect).z
		else:
			closest_dist_to_cam = min(closest_dist_to_cam, -main_cam.to_local(intersect).z)
	
	camera.near = max(main_cam.near, closest_dist_to_cam + cull_bias)
	match main_cam.projection:
		Camera.PROJECTION_PERSPECTIVE:
			camera.set_perspective(main_cam.fov, camera.near, main_cam.far)
		Camera.PROJECTION_ORTHOGONAL:
			camera.set_orthogonal(main_cam.size, camera.near, main_cam.far)
		Camera.PROJECTION_FRUSTUM:
			camera.set_frustum(main_cam.size, main_cam.frustum_offset, camera.near, main_cam.far)


class PortalSort:
	var cam_trans: Transform
	
	func _init(_cam_trans: Transform) -> void:
		self.cam_trans = _cam_trans
	
	func sort(a: Portal, b: Portal) -> bool:
		if abs((cam_trans.inverse() * a.global_transform.origin).z) < abs((cam_trans.inverse() * b.global_transform.origin).z):
			return true
		return false

