class_name VoxelGenerator

var map : Array[Voxel]
var map_dict : Dictionary[Vector3i, Voxel]
const sides = 6
var settings : GenerationSettings
var surface_voxels : Array[Voxel]
var atlas_settings: Resource

const VOXEL_ATLAS_SETTINGS_SCRIPT = preload("res://addons/voxel_worldgen/resources/voxel_atlas_settings.gd")

# Define base hexagon
const base_vertices = [
	Vector3(0.5, 0.0, -0.866),  # Left
	Vector3(1.0, 0.0, 0.0),  # Top-right
	Vector3(0.5, 0.0, 0.866),  # Bottom-right
	Vector3(-0.5, 0.0, 0.866),  # Bottom-left
	Vector3(-1.0, 0.0, 0.0),  # Left
	Vector3(-0.5, 0.0, -0.866)  # Top-left
	]


func generate_chunk(_map : Array[Voxel], interval) -> Chunk:
	map = _map
	settings = WorldMap.world_settings
	if atlas_settings == null:
		atlas_settings = VOXEL_ATLAS_SETTINGS_SCRIPT.new()
	var verts = PackedVector3Array()
	var indices = PackedInt32Array()
	var uvs = PackedVector2Array()
	
	var process_vector = process_voxels()
	print("Correction passes: ", process_vector.x, ". Total voxels removed: ", process_vector.y)
	interval["Processing Voxels total -- "] = Time.get_ticks_msec()
	
	for voxel in map:
		assign_type(voxel)
		var prism = build_hex_prism(voxel)
		var v_offset = verts.size() # start at last indice to not overwrite old ones
		verts.append_array(prism.verts)
		uvs.append_array(prism.uvs)
		for indice in prism.indices:
			indices.append(indice + v_offset)

	interval["Build voxels -- "] = Time.get_ticks_msec()

	## Create surface
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for v_index in range(verts.size()):
		surface.set_uv(uvs[v_index])
		surface.set_smooth_group(settings.shading)
		surface.add_vertex(verts[v_index])

	for i in indices:
		surface.add_index(i)

	surface.optimize_indices_for_cache()
	surface.generate_normals()
	surface.generate_tangents()
	WorldMap.set_map(map, surface_voxels)
	
	return prepared_chunk(surface)


func prepared_chunk(surface) -> Chunk:
	var chunk = Chunk.new()
	chunk.mesh = surface.commit()
	chunk.voxels = map
	chunk.material_override = settings.material
	return chunk


func process_voxels() -> Vector2i:
	# Prepare counters
	var passes = 0
	var total_removed = 0
	
	for voxel in map: # do this once
		normalize_voxel_noise(voxel)
		assign_air_probability(voxel)
		map_dict[voxel.grid_position_xyz] = voxel
	
	while passes < 20:
		var removed = 0
		for i in range(map.size()):
			var voxel = map[i]
			if voxel.type != VoxelData.voxel_type.AIR:
				if shape_geometry(voxel):
					removed += 1
		if removed < 1:
			break
		total_removed += removed
		passes += 1
	
	return Vector2i(passes, total_removed)


func normalize_voxel_noise(voxel: Voxel):
	# Normalize noise to [0,1] based on min/max
	var n = voxel.noise
	var min_n = WorldMap.noise_range.x
	var max_n = WorldMap.noise_range.y
	var normalized = clamp((n - min_n) / (max_n - min_n), 0.0, 0.9999)
	voxel.noise = normalized


func assign_air_probability(voxel: Voxel) -> void:
	var noise_contribution : float = voxel.noise
	var y : float = voxel.grid_position_xyz.y
	var normalized_height : float = clampf(y / settings.max_height, 0.0, 1.0)

	var combined_probability : float = (1.0 - settings.noise_height_bias) * noise_contribution \
									 + settings.noise_height_bias * normalized_height
	voxel.air_probability = clampf(combined_probability, 0.0, 1.0)


func shape_geometry(prism) -> bool:
	# Ensure solid first layer
	if settings.solid_first_layer and prism.grid_position_xyz.y == 0:
		prism.type = VoxelData.voxel_type.BEDROCK
		return false
	
	# Convert to air
	if prism.air_probability > settings.ground_to_air_ratio:
		prism.type = VoxelData.voxel_type.AIR
		return true
	
	# Flatten buffer
	if prism.buffer and settings.flat_buffer:
		prism.type = VoxelData.voxel_type.AIR
		return true
	
	# Remove overhang
	if settings.remove_overhang:
		var below = prism.grid_position_xyz
		below.y -= 1
		if below.y >= 1 and air_at_pos(below):
			prism.type = VoxelData.voxel_type.AIR
			return true
	
	# Terrace shaping
	if settings.terrace_steps >= 1:
		var table = VoxelData.get_tile_neighbor_table(prism.grid_position_xz.x)
		for dir in table:
			var neighbor_pos = Vector3i(prism.grid_position_xyz.x + dir.x,
										prism.grid_position_xyz.y - settings.terrace_steps,
										prism.grid_position_xyz.z + dir.y)
			if air_at_pos(neighbor_pos):
				prism.type = VoxelData.voxel_type.AIR
				return true
	
	return false


func assign_type(voxel: Voxel):
	if voxel.type == VoxelData.voxel_type.AIR or voxel.type == VoxelData.voxel_type.BEDROCK:
		return

	var tiles = VoxelData.tile_map.size()
	var n = voxel.noise

	var enum_index = int(floor(n * float(tiles)))
	if enum_index == 0: # turn air into something else
		enum_index = 5 # Sand, could also be randomized
	elif enum_index == 1 and voxel.grid_position_xyz.y != 0: #turn bedrock into something else
		enum_index = 5
	
	# surface replacement
	var neighbor_above: Vector3i = voxel.grid_position_xyz + Vector3i(0,1,0)
	var neighbor: Voxel = map_dict.get(neighbor_above)
	var tile_dict : Dictionary = VoxelData.tile_map.get(enum_index as VoxelData.voxel_type)
	if tile_dict.has("surface"):
		if neighbor:
			if neighbor.type == VoxelData.voxel_type.AIR:
				enum_index = tile_dict["surface"]
	if tile_dict.has("underground"):
		if neighbor:
			if neighbor.type != VoxelData.voxel_type.AIR:
				enum_index = tile_dict["underground"]
	
	voxel.type = enum_index as VoxelData.voxel_type


func draw_face_towards(neighbor_pos : Vector3i) -> bool:
	var neighbor = map_dict.get(neighbor_pos)
	if neighbor:
		if neighbor.type == VoxelData.voxel_type.AIR:
			return true
		else:
			return false
	return true


func air_at_pos(pos) -> bool:
	var neighbor : Voxel = map_dict.get(pos)
	if neighbor and neighbor.type == VoxelData.voxel_type.AIR:
		return true
	return false


# Returns verts indices and uvs for a voxel
func build_hex_prism(voxel: Voxel) -> Dictionary:
	var verts = PackedVector3Array()
	var uvs   = PackedVector2Array()
	var indices = PackedInt32Array()
	if voxel.type == VoxelData.voxel_type.AIR:
		return {"verts": verts, "uvs": uvs, "indices": indices}

	var top_start = verts.size()
	var size = settings.voxel_size
	var height = settings.voxel_height
	var pos = voxel.world_position
	var top_offset = Vector3(0, height, 0)
	var tiles : Dictionary = VoxelData.tile_map.get(voxel.type)
	var top_tile = tiles["top"]
	var side_tile = tiles["side"]
	var bottom_tile = tiles.get("bottom", top_tile)
	var dirs = VoxelData.get_tile_neighbor_table(voxel.grid_position_xyz.x)
	var neighbor : Vector3i
	
	## TOP!
	neighbor = voxel.grid_position_xyz
	neighbor.y += 1
	if draw_face_towards(neighbor):
		voxel.surface_voxel = true
		surface_voxels.append(voxel)
		for i in range(sides):
			var angle = TAU * float(i) / float(sides)
			var x = cos(angle) * size
			var z = sin(angle) * size
			verts.append(pos + Vector3(x, height, z))
			# map inside [0,1] as circle
			uvs.append(atlas_uv(Vector2(0.5 + cos(angle)*0.5, 0.5 + sin(angle)*0.5), top_tile))
		# center vertex
		verts.append(pos + top_offset)
		uvs.append(atlas_uv(Vector2(0.5, 0.5), top_tile))
		# top triangles
		for i in range(sides):
			indices.append(top_start + i)
			indices.append(top_start + ((i + 1) % sides))
			indices.append(top_start + sides)  # center
	
	## BOTTOM
	neighbor = voxel.grid_position_xyz
	neighbor.y -= 1
	if draw_face_towards(neighbor) and settings.draw_bottom:
		var bottom_start = verts.size()
		for i in range(sides):
			var angle = TAU * float(i) / float(sides)
			var x = cos(angle) * size
			var z = sin(angle) * size
			verts.append(pos + Vector3(x, 0, z))
			uvs.append(atlas_uv(Vector2(0.5 + cos(angle)*0.5, 0.5 + sin(angle)*0.5), bottom_tile))
		verts.append(pos) # center
		uvs.append(atlas_uv(Vector2(0.5,0.5), bottom_tile))
		# triangles (note: winding reversed so normal faces down)
		for i in range(sides):
			indices.append(bottom_start + sides)  # center
			indices.append(bottom_start + ((i + 1) % sides))
			indices.append(bottom_start + i)

	# Sides
	for i in range(sides):
		neighbor = Vector3i(voxel.grid_position_xyz.x + dirs[i].x,
							voxel.grid_position_xyz.y,
							voxel.grid_position_xyz.z + dirs[i].y)
		if not draw_face_towards(neighbor):
			continue  # skip this side entirely
			
		# base_vertices ensure correct ordering
		var bv0 = base_vertices[i]   * size
		var bv1 = base_vertices[(i + 1) % sides] * size

		var p0 = Vector3(bv0.x, 0.0, bv0.z) + pos
		var p1 = Vector3(bv1.x, 0.0, bv1.z) + pos
		var p2 = p0 + top_offset
		var p3 = p1 + top_offset

		var side_start = verts.size()
		verts.append(p0); uvs.append(atlas_uv(Vector2(0,0), side_tile))
		verts.append(p1); uvs.append(atlas_uv(Vector2(1,0), side_tile))
		verts.append(p2); uvs.append(atlas_uv(Vector2(0,1), side_tile))
		verts.append(p3); uvs.append(atlas_uv(Vector2(1,1), side_tile))

		indices.append(side_start + 0)
		indices.append(side_start + 1)
		indices.append(side_start + 2)
		indices.append(side_start + 1)
		indices.append(side_start + 3)
		indices.append(side_start + 2)
	
	# Debug: check UV ranges
	for u in uvs:
		if u.x < 0 or u.x > 1 or u.y < 0 or u.y > 1:
			push_warning("UV out of range: ", u, " for voxel type ", voxel.type)
	#print("Voxel type: ", voxel.type, " → Tile: ", tile, " → Sample UVs: ", uvs.slice(0, 4))

	return {
		"verts": verts,
		"uvs": uvs,
		"indices": indices
	}


func atlas_uv(local_uv: Vector2, tile: Vector2i) -> Vector2:
	# Pixel bounds of usable tile
	var tile_margin: Vector2i = atlas_settings.get("tile_margin")
	var tile_stride: Vector2i = atlas_settings.get("tile_stride")
	var tile_size: Vector2i = atlas_settings.get("tile_size")
	var atlas_resolution: Vector2i = atlas_settings.get("atlas_resolution")
	var pixel_min: Vector2i = tile_margin + tile * tile_stride
	var pixel_max: Vector2i = pixel_min + tile_size
	
	# Convert to normalized [0..1] UVs
	var uv_min: Vector2 = Vector2(pixel_min) / Vector2(atlas_resolution)
	var uv_max: Vector2 = Vector2(pixel_max) / Vector2(atlas_resolution)
	
	# Map local_uv [0..1] into this rectangle
	return uv_min + local_uv * (uv_max - uv_min)
