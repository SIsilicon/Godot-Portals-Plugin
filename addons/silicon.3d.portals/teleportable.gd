extends Node

var prev_portal_pos := {}

func _process(_delta: float) -> void:
	if not get_viewport().has_meta(Portal._PORTAL_LIST):
		return
	
	var parent := get_parent()
	var position: Vector3 = parent.global_transform.origin
	var portals: Array = get_viewport().get_meta(Portal._PORTAL_LIST)
	var portals_going_through := []
	for portal in portals:
		if not portal.is_working():
			continue
		
		var portal_pos: Vector3 = portal.to_local(position)
		if not prev_portal_pos.has(portal):
			prev_portal_pos[portal] = portal_pos
		
		if prev_portal_pos[portal] != portal_pos:
			var prev_pos: Vector3 = prev_portal_pos[portal]
			var prev_side := prev_pos.dot(Vector3.FORWARD)
			var curr_side := portal_pos.dot(Vector3.FORWARD)
			if prev_side < 0.0 and curr_side > 0.0 and (_by_portal(prev_pos) or _by_portal(portal_pos)):
				portals_going_through.append(portal)
		
		prev_portal_pos[portal] = portal_pos
	
	for portal in portals_going_through:
		parent.global_transform = portal.teleport_transform(parent.global_transform)
	
	if not portals_going_through.empty():
		prev_portal_pos.clear()
		for portal in portals:
			if portal.is_working():
				portal.last_frame_active = 0


func _by_portal(local_coords: Vector3) -> bool:
	return clamp(local_coords.x, -0.5, 0.5) == local_coords.x and clamp(local_coords.y, -0.5, 0.5) == local_coords.y
