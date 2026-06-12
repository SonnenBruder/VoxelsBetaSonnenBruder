@tool
extends EditorPlugin

const WORLD_MAP_AUTOLOAD := "WorldMap"
const VOXEL_DATA_AUTOLOAD := "VoxelData"
const WORLD_MAP_PATH := "res://addons/voxel_worldgen/autoloads/world_map.gd"
const VOXEL_DATA_PATH := "res://addons/voxel_worldgen/autoloads/voxel_data.gd"


func _enter_tree() -> void:
	_add_autoload_if_missing(VOXEL_DATA_AUTOLOAD, VOXEL_DATA_PATH)
	_add_autoload_if_missing(WORLD_MAP_AUTOLOAD, WORLD_MAP_PATH)


func _exit_tree() -> void:
	_remove_autoload_if_owned(WORLD_MAP_AUTOLOAD, WORLD_MAP_PATH)
	_remove_autoload_if_owned(VOXEL_DATA_AUTOLOAD, VOXEL_DATA_PATH)


func _add_autoload_if_missing(autoload_name: String, script_path: String) -> void:
	if ProjectSettings.has_setting("autoload/%s" % autoload_name):
		return
	add_autoload_singleton(autoload_name, script_path)


func _remove_autoload_if_owned(autoload_name: String, script_path: String) -> void:
	var setting_key := "autoload/%s" % autoload_name
	if not ProjectSettings.has_setting(setting_key):
		return

	var configured_path := str(ProjectSettings.get_setting(setting_key))
	if configured_path == script_path or configured_path == "*" + script_path:
		remove_autoload_singleton(autoload_name)

