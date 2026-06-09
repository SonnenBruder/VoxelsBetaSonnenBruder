extends Node

signal world_generated(chunk: Chunk, voxel_count: int)
signal generation_profile_ready(profile: Dictionary)

# Dependencies
## Generation settings resource used for current world build.
@export var settings : GenerationSettings
@export_category("Dependencies")
## Parent node that receives generated chunk instances.
@export var chunks_root : Node3D

@export_category("Fallback Paths")
## Relative fallback path used to resolve chunks_root when unset.
@export var chunks_root_path: NodePath = ^"../../Chunks"

@export_category("Behavior")
## Auto-run regeneration when node enters scene tree.
@export var generate_on_ready := true


## Starting point: Generate random seed, create tiles, emit completion signal
func _ready() -> void:
	if not generate_on_ready:
		return
	regenerate_world()


func regenerate_world() -> void:
	resolve_dependencies()
	if settings == null:
		push_error("WorldGenerator: GenerationSettings missing")
		return
	if chunks_root == null:
		push_error("WorldGenerator: chunks_root missing")
		return

	WorldMap.clear_map()
	WorldMap.world_settings = settings
	init_seed()
	var children = chunks_root.get_children() + get_children()
	for c in children:
		c.free()
	call_deferred("generate_world")


func resolve_dependencies() -> void:
	if chunks_root == null and not chunks_root_path.is_empty():
		chunks_root = get_node_or_null(chunks_root_path) as Node3D

# Randomize if no seed has been set
func init_seed():
	if settings.map_seed == 0 or settings.map_seed == null:
		settings.noise.seed = randi()
	else:
		settings.noise.seed = settings.map_seed


## Start of world_generation, time each step
func generate_world():
	var starttime = Time.get_ticks_msec()
	var interval = {"Start of Generation!" : starttime}
	
	## Get all positions through the gridmapper
	var mapper = GridMapper.new()
	var voxels = mapper.calculate_map_positions()
	interval["Calculate Map Positions -- "] = Time.get_ticks_msec()

	var vg = VoxelGenerator.new()
	var new_chunk = vg.generate_chunk(voxels, interval)
	chunks_root.add_child(new_chunk)
	new_chunk.init_chunk()
	interval["Create Voxel Mesh -- "] = Time.get_ticks_msec()

	var profile = build_generation_profile(starttime, interval)
	print_generation_results(profile)
	emit_signal("generation_profile_ready", profile)
	emit_signal("world_generated", new_chunk, voxels.size())
	#Debugger.draw_voxel_dictionary(WorldMap.surface_layer)


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
