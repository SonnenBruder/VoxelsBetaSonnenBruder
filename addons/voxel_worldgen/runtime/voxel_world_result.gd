extends RefCounted
class_name VoxelWorldResult

var seed_used: int
var settings: GenerationSettings
var chunk: Chunk
var voxel_count: int
var surface_count: int
var full_voxels_by_grid: Dictionary = {}
var surface_tiles_by_coord: Dictionary = {}
var generation_profile: Dictionary = {}
var noise_range: Vector2
var metadata: Dictionary = {}
