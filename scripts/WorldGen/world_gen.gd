extends Node

signal world_generated(chunk: Chunk, voxel_count: int)

# Dependencies
@export var settings : GenerationSettings
@export_category("Dependencies")
@export var chunks_root : Node3D
@export var object_placer : Node
@export var interaction_tracker: Node
@export var results_label: RichTextLabel

@export_category("Fallback Paths")
@export var chunks_root_path: NodePath = ^"../../Chunks"
@export var object_placer_path: NodePath = ^"../ObjectPlacer"
@export var interaction_tracker_path: NodePath = ^"../Interaction_tracker"
@export var results_label_path: NodePath = ^"../../Control/VBoxContainer/RichTextLabel"

@export_category("Behavior")
@export var generate_on_ready := true
@export var initialize_interaction := true
@export var log_results_to_label := true


## Starting point: Generate a random seed, create the tiles, place POI's
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
	if object_placer and object_placer.has_method("clear_objects"):
		object_placer.call("clear_objects")
	call_deferred("generate_world")


func resolve_dependencies() -> void:
	if chunks_root == null and not chunks_root_path.is_empty():
		chunks_root = get_node_or_null(chunks_root_path) as Node3D
	if object_placer == null and not object_placer_path.is_empty():
		object_placer = get_node_or_null(object_placer_path)
	if interaction_tracker == null and not interaction_tracker_path.is_empty():
		interaction_tracker = get_node_or_null(interaction_tracker_path)
	if results_label == null and not results_label_path.is_empty():
		results_label = get_node_or_null(results_label_path) as RichTextLabel

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

	## Spawn villages and units
	if settings.spawn_villages_and_units and object_placer:
		var placeable = get_placeable_voxels()
		if object_placer.has_method("place_villages"):
			object_placer.call("place_villages", placeable, settings.spacing)
		if object_placer.has_method("create_starting_units"):
			object_placer.call("create_starting_units", floori(settings.radius*0.5))
		interval["Spawn Villages -- "] = Time.get_ticks_msec()
	elif settings.spawn_villages_and_units:
		push_warning("WorldGenerator: spawn_villages_and_units enabled but object_placer missing")
	
	print_generation_results(starttime, interval)
	if initialize_interaction and interaction_tracker and interaction_tracker.has_method("init"):
		interaction_tracker.call("init")
	emit_signal("world_generated", new_chunk, voxels.size())
	#Debugger.draw_voxel_dictionary(WorldMap.surface_layer)


## This mess of a function loops through the timing results of generate_world and prints them
func print_generation_results(start : float, dict : Dictionary):
	print("\n")
	if log_results_to_label and results_label:
		results_label.text = ""
	var last_val = start
	var total = 0
	var unit = "ms"
	
	for key in dict:
		var val = dict[key]
		if val == start:
			continue
		var passed = val - last_val
		if log_results_to_label and results_label:
			results_label.text += "[b]" + str(key) + "[/b]" + "[i]" + str(passed) + "ms\n" + "[/i]"
		last_val = val
		total += passed

	if total > 999: 
		unit = "s"
		total *= 0.001

	print("Total completion time: ", total, unit)
	if log_results_to_label and results_label:
		results_label.text += "[b]Total completion time: [/b][i]" + str(total) + unit + "[/i]"


## Ignore buffer and ocean to return for object placer
func get_placeable_voxels() -> Array[Voxel]:
	var placeable_tiles : Array[Voxel] = []
	for key in WorldMap.surface_layer:
		var voxel = WorldMap.surface_layer[key]
		if voxel.buffer or not voxel.placeable:
			continue
		placeable_tiles.append(voxel)
	print(str(placeable_tiles.size()) + " placeable tiles")
	return placeable_tiles
