tool
extends Node

var _portals := {}
var _sub_portals := []


func _process(_delta : float) -> void:
	pass


func create_portal() -> int:
	var portal := PortalData.new()
	var id := hash(portal)
	_portals[id] = portal
	return id


func register_to_viewport(portal: int, viewport: Viewport) -> void:
	var node: Spatial = _portals[portal].node
	if node.is_inside_tree():
		return
	
	viewport.add_child(node)
	_portals[portal].viewport = viewport


func unregister_from_viewport(portal: int) -> void:
	var node: Spatial = _portals[portal].node
	if not node.is_inside_tree():
		return
	
	_portals[portal].remove_child(node)
	_portals[portal].viewport = null


func set_portal_transform(portal: int, transform: Transform) -> void:
	_portals[portal].node.transform = transform


func set_portal_link(portal: int, link_to: int) -> void:
	if not _portals[portal].node.is_inside_tree() or not _portals[link_to].node.is_inside_tree():
		return
	_portals[portal].link = _portals[link_to]
	_portals[link_to].link = _portals[portal]


func set_portal_active_material(portal: int, material: ShaderMaterial) -> void:
	var portal_data: PortalData = _portals[portal]
	
	if material.shader != portal_data.active_material.shader:
		portal_data.active_material = material
		portal_data.surface.material_override = material.duplicate()
	
	if portal_data.active_material:
		var view_tex := portal_data.viewport.get_texture()
		portal_data.surface.material_override.set_shader_param("portal_texture", view_tex)


func set_portal_default_material(portal: int, material: Material) -> void:
	var portal_data: PortalData = _portals[portal]
	portal_data.default_material = material
	portal_data.default.material_override = material


func portal_teleport_transform(portal: int, transform := Transform.IDENTITY) -> Transform:
	var portal_data: PortalData = _portals[portal]
	if not portal_data.link:
		return transform
	return portal_data.link.sender.transform.orthonormalized() * portal_data.node.transform.orthonormalized().inverse() * transform


func free_portal(portal: int) -> void:
	unregister_from_viewport(portal)
	_portals[portal].free()
	_portals.erase(portal)


class PortalData extends Object:
	var link: PortalData
	
	var node: Spatial
	var sender: Spatial
	var viewport: Viewport
	
	var surface: MeshInstance
	var default: MeshInstance
	var active_material: ShaderMaterial
	var default_material: Material
	
	func _init() -> void:
		node = preload("portal.tscn").instance()
		sender = node.get_node("Sender")
	
	
	func free() -> void:
		node.queue_free()
		link.link = null

