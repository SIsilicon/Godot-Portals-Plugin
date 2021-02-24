# Copyright © 2020 Roujel Williams - MIT License
# See `LICENSE.md` included in the source distribution for details.
tool
extends EditorPlugin


func _enter_tree() -> void:
	add_autoload_singleton("PortalServer", "res://addons/silicon.3d.portals/portal_server.gd")


func _exit_tree() -> void:
	remove_autoload_singleton("PortalServer")
