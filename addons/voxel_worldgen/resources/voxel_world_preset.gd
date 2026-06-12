extends Resource
class_name VoxelWorldPreset

enum GenerationRole {OVERWORLD, BATTLEFIELD}

@export var generation_seed := 0
@export var generation_settings: GenerationSettings
@export var atlas_settings: Resource
@export var terrain_strategy: Resource
@export var weight_strategies: Array[Resource] = []

@export_category("Output")
@export var include_full_voxel_map := true
@export var include_surface_map := true
@export var include_mesh_chunk := true
@export var include_debug_profile := true
@export var write_to_world_map := true

@export_category("Context")
@export var metadata_defaults: Dictionary = {}
@export var generation_role: GenerationRole = GenerationRole.OVERWORLD
@export var parent_world_seed := 0
@export var parent_surface_coord := Vector2i.ZERO
@export var battlefield_size := 0
@export var battlefield_context: Dictionary = {}
