extends Node
class_name VoxelWorldGenerator

signal world_generated(chunk: Chunk, voxel_count: int)
signal world_result_ready(result: VoxelWorldResult)
signal generation_profile_ready(profile: Dictionary)
signal generation_started(seed_used: int)

const DEFAULT_TERRAIN_STRATEGY_SCRIPT = preload("res://addons/voxel_worldgen/terrain/default_terrain_strategy.gd")
const VOXEL_ATLAS_SETTINGS_SCRIPT = preload("res://addons/voxel_worldgen/resources/voxel_atlas_settings.gd")
const VOXEL_GENERATION_CONTEXT_SCRIPT = preload("res://addons/voxel_worldgen/runtime/voxel_generation_context.gd")

# Dependencies
## Optional preset that can fill settings, atlas, strategy, output, seed, and metadata defaults.
@export var preset: Resource
## Generation settings resource used for current world build.
@export var settings : GenerationSettings
@export_category("Dependencies")
## Parent node that receives generated chunk instances.
@export var chunks_root : Node3D
## Optional atlas dimension resource. Defaults preserve the current texture atlas.
@export var atlas_settings: Resource
## Optional terrain generator strategy. Defaults to current GridMapper + VoxelGenerator flow.
@export var terrain_strategy: Resource
## Optional tile scoring strategies. Results write into VoxelSurfaceTile.weights.
@export var weight_strategies: Array[Resource] = []

@export_category("Fallback Paths")
## Relative fallback path used to resolve chunks_root when unset.
@export var chunks_root_path: NodePath = ^"../../Chunks"

@export_category("Behavior")
## Auto-run regeneration when node enters scene tree.
@export var generate_on_ready := true
## Optional seed override. Use 0 to read settings.map_seed; if both are 0, a random seed is generated and reported.
@export var generation_seed := 0

@export_category("Output")
@export var output_surface_data := true
@export var output_full_voxel_data := true
@export var include_mesh_chunk := true
@export var include_debug_profile := true

var last_result: VoxelWorldResult
var generation_context


## Starting point: Generate random seed, create tiles, emit completion signal
func _ready() -> void:
	if not generate_on_ready:
		return
	regenerate_world()


func regenerate_world() -> void:
	resolve_dependencies()
	apply_preset()
	if settings == null:
		push_error("WorldGenerator: GenerationSettings missing")
		return
	if chunks_root == null:
		push_error("WorldGenerator: chunks_root missing")
		return

	clear_world()
	WorldMap.world_settings = settings
	prepare_generation_context()
	emit_signal("generation_started", generation_context.seed_used)
	call_deferred("generate_world")


func clear_world() -> void:
	WorldMap.clear_map()
	last_result = null
	generation_context = null
	if chunks_root != null:
		for child in chunks_root.get_children():
			child.free()
	for child in get_children():
		child.free()


func resolve_dependencies() -> void:
	if chunks_root == null and not chunks_root_path.is_empty():
		chunks_root = get_node_or_null(chunks_root_path) as Node3D

# Randomize if no seed has been set
func init_seed():
	prepare_generation_context()


func prepare_generation_context() -> void:
	var requested_seed := resolve_requested_seed()
	var seed_used = resolve_seed(requested_seed)
	var random = RandomNumberGenerator.new()
	random.seed = seed_used

	if settings.noise == null:
		settings.noise = FastNoiseLite.new()
	settings.noise.seed = seed_used

	generation_context = VOXEL_GENERATION_CONTEXT_SCRIPT.new()
	generation_context.settings = settings
	generation_context.requested_seed = requested_seed
	generation_context.seed_used = seed_used
	generation_context.random = random
	generation_context.atlas_settings = resolve_atlas_settings()
	generation_context.metadata = build_generation_metadata()


func apply_preset() -> void:
	if preset == null:
		return

	var preset_settings = preset.get("generation_settings") as GenerationSettings
	if preset_settings != null:
		settings = preset_settings

	var preset_atlas = preset.get("atlas_settings") as Resource
	if preset_atlas != null:
		atlas_settings = preset_atlas

	var preset_terrain = preset.get("terrain_strategy") as Resource
	if preset_terrain != null:
		terrain_strategy = preset_terrain

	var preset_weights = preset.get("weight_strategies")
	if preset_weights is Array:
		weight_strategies.clear()
		for strategy in preset_weights:
			if strategy is Resource:
				weight_strategies.append(strategy)

	var include_full = preset.get("include_full_voxel_map")
	if include_full != null:
		output_full_voxel_data = bool(include_full)

	var include_surface = preset.get("include_surface_map")
	if include_surface != null:
		output_surface_data = bool(include_surface)

	var include_chunk = preset.get("include_mesh_chunk")
	if include_chunk != null:
		include_mesh_chunk = bool(include_chunk)

	var include_profile = preset.get("include_debug_profile")
	if include_profile != null:
		include_debug_profile = bool(include_profile)


func resolve_requested_seed() -> int:
	if generation_seed != 0:
		return generation_seed

	if preset != null:
		var preset_seed := int(preset.get("generation_seed"))
		if preset_seed != 0:
			return preset_seed

		var role := int(preset.get("generation_role"))
		var parent_seed := int(preset.get("parent_world_seed"))
		if role == 1 and parent_seed != 0:
			var parent_coord: Vector2i = preset.get("parent_surface_coord")
			var context_value = preset.get("battlefield_context")
			var context: Dictionary = context_value.duplicate(true) if context_value is Dictionary else {}
			return derive_child_seed(parent_seed, parent_coord, context)

	if settings != null:
		return settings.map_seed
	return 0


func derive_child_seed(parent_seed: int, parent_coord: Vector2i, battlefield_context: Dictionary) -> int:
	var derived: int = abs(hash("%s:%s:%s" % [parent_seed, parent_coord, battlefield_context]))
	if derived == 0:
		return parent_seed
	return derived


func build_generation_metadata() -> Dictionary:
	var metadata: Dictionary = {}
	if preset == null:
		return metadata

	var defaults = preset.get("metadata_defaults")
	if defaults is Dictionary:
		metadata = defaults.duplicate(true)

	var role := int(preset.get("generation_role"))
	metadata["generation_role"] = role
	if role == 1:
		metadata["parent_world_seed"] = int(preset.get("parent_world_seed"))
		metadata["parent_surface_coord"] = preset.get("parent_surface_coord")
		metadata["battlefield_size"] = int(preset.get("battlefield_size"))
		var battlefield_context_value = preset.get("battlefield_context")
		metadata["battlefield_context"] = battlefield_context_value.duplicate(true) if battlefield_context_value is Dictionary else {}
	return metadata


func resolve_seed(requested_seed: int) -> int:
	if requested_seed != 0:
		return requested_seed

	var seed_random = RandomNumberGenerator.new()
	seed_random.randomize()
	return seed_random.randi()


func resolve_atlas_settings() -> Resource:
	if atlas_settings != null:
		return atlas_settings
	return VOXEL_ATLAS_SETTINGS_SCRIPT.new()


func resolve_terrain_strategy() -> Resource:
	if terrain_strategy != null:
		return terrain_strategy
	return DEFAULT_TERRAIN_STRATEGY_SCRIPT.new()


## Start of world_generation, time each step
func generate_world():
	resolve_dependencies()
	apply_preset()
	if settings == null:
		push_error("WorldGenerator: GenerationSettings missing")
		return
	if chunks_root == null:
		push_error("WorldGenerator: chunks_root missing")
		return
	if generation_context == null:
		WorldMap.world_settings = settings
		prepare_generation_context()
		emit_signal("generation_started", generation_context.seed_used)

	var starttime = Time.get_ticks_msec()
	var interval = {"Start of Generation!" : starttime}
	generation_context.interval = interval
	
	var active_strategy = resolve_terrain_strategy()
	if not active_strategy.has_method("generate"):
		push_error("WorldGenerator: terrain_strategy must implement generate(context)")
		return

	var generation_output = active_strategy.generate(generation_context)
	var new_chunk = generation_output.get("chunk") as Chunk
	var voxels = generation_output.get("voxels", [])
	if new_chunk == null:
		push_error("WorldGenerator: terrain_strategy did not return a Chunk")
		return
	chunks_root.add_child(new_chunk)
	new_chunk.init_chunk()
	interval["Create Voxel Mesh -- "] = Time.get_ticks_msec()

	var profile = build_generation_profile(starttime, interval)
	last_result = build_world_result(new_chunk, voxels.size(), profile)
	print_generation_results(profile)
	emit_signal("generation_profile_ready", profile)
	emit_signal("world_result_ready", last_result)
	emit_signal("world_generated", new_chunk, voxels.size())
	#Debugger.draw_voxel_dictionary(WorldMap.surface_layer)


func get_last_result() -> VoxelWorldResult:
	return last_result


func get_surface_tile_at_coord(coord: Vector2i) -> VoxelSurfaceTile:
	if last_result == null:
		return null
	return last_result.surface_tiles_by_coord.get(coord) as VoxelSurfaceTile


func get_voxel_at_grid_coord(coord: Vector3i) -> Voxel:
	if last_result == null:
		return null
	return last_result.full_voxels_by_grid.get(coord) as Voxel


func build_world_result(chunk: Chunk, voxel_count: int, profile: Dictionary) -> VoxelWorldResult:
	var result = VoxelWorldResult.new()
	result.seed_used = generation_context.seed_used if generation_context != null else settings.noise.seed
	result.settings = settings
	result.chunk = chunk if include_mesh_chunk else null
	result.voxel_count = voxel_count
	result.full_voxels_by_grid = WorldMap.map_as_dict.duplicate(false) if output_full_voxel_data else {}
	result.generation_profile = profile.duplicate(true) if include_debug_profile else {}
	result.noise_range = WorldMap.noise_range
	result.metadata = generation_context.metadata.duplicate(true) if generation_context != null else {}
	result.surface_tiles_by_coord = build_surface_tiles_by_coord() if output_surface_data else {}
	apply_weight_strategies(result)
	result.surface_count = result.surface_tiles_by_coord.size()
	return result


func build_surface_tiles_by_coord() -> Dictionary:
	var surface_tiles: Dictionary = {}
	for voxel: Voxel in WorldMap.surface_layer.values():
		var tile = VoxelSurfaceTile.new()
		tile.coord_2d = voxel.grid_position_xz
		tile.top_grid_coord = voxel.grid_position_xyz
		tile.world_position = voxel.world_position
		tile.height = voxel.grid_position_xyz.y
		tile.terrain_type = voxel.type
		tile.is_empty = voxel.type == VoxelData.voxel_type.AIR
		tile.passable = not voxel.water and voxel.type != VoxelData.voxel_type.AIR
		tile.placeable = voxel.placeable and not voxel.buffer
		tile.metadata = {
			"noise": voxel.noise,
			"air_probability": voxel.air_probability,
			"buffer": voxel.buffer,
			"water": voxel.water,
			"surface_voxel": voxel.surface_voxel
		}
		tile.source_voxel = voxel
		surface_tiles[tile.coord_2d] = tile
	return surface_tiles


func apply_weight_strategies(result: VoxelWorldResult) -> void:
	if weight_strategies.is_empty() or result.surface_tiles_by_coord.is_empty():
		return

	for strategy in weight_strategies:
		if strategy == null:
			continue
		if not strategy.has_method("calculate_weight"):
			push_warning("WorldGenerator: weight strategy missing calculate_weight")
			continue

		var weight_id: StringName = &"weight"
		if strategy.has_method("get_weight_id"):
			weight_id = strategy.get_weight_id()

		for tile: VoxelSurfaceTile in result.surface_tiles_by_coord.values():
			var weight = float(strategy.calculate_weight(tile, result, settings))
			tile.weights[weight_id] = weight
			if tile.source_voxel != null and weight_id == &"village":
				tile.source_voxel.village_weight = weight


func build_generation_profile(start : float, timestamps : Dictionary) -> Dictionary:
	var last_val = start
	var total_ms = 0.0
	var lines : Array[Dictionary] = []
	for key in timestamps:
		var val = float(timestamps[key])
		if val == start:
			continue
		var passed = val - last_val
		lines.append({
			"label": str(key),
			"duration_ms": passed
		})
		last_val = val
		total_ms += passed
	return {
		"lines": lines,
		"total_ms": total_ms
	}


func print_generation_results(profile : Dictionary):
	print("\n")
	var lines : Array[Dictionary] = profile.get("lines", [])
	for line in lines:
		print(line.get("label", "Step"), line.get("duration_ms", 0.0), "ms")

	var total = float(profile.get("total_ms", 0.0))
	var unit = "ms"
	var display_total = total

	if total > 999: 
		unit = "s"
		display_total *= 0.001

	print("Total completion time: ", display_total, unit)
