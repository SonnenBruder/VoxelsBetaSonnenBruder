extends RefCounted
class_name VoxelSurfaceTile

var coord_2d: Vector2i
var top_grid_coord: Vector3i
var world_position: Vector3
var height: int
var terrain_type: int
var is_empty: bool
var passable: bool
var placeable: bool
var weights: Dictionary = {}
var metadata: Dictionary = {}
var source_voxel: Voxel
