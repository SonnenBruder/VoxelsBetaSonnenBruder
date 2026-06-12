extends MeshInstance3D
class_name Chunk

var voxels : Array[Voxel]
var voxel_layers: Dictionary[int, Array] = {}


func init_chunk():
	generate_collider()
	add_to_group("voxels")
	fill_pos_dict()


func generate_collider():
	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = mesh.create_trimesh_shape()
	col.shape = shape
	add_child(body)
	body.add_child(col)


func fill_pos_dict():
	for v: Voxel in voxels:
		var y = v.grid_position_xyz.y
		if not voxel_layers.has(y):
			voxel_layers[y] = []
			#print("Voxel layer: ", y)
		voxel_layers[y].append(v)


# Find a voxel at a given location
# We cant just compare against where the user clicked since voxels can have various sizes/offsets!
# perform greedy-first-search across the relevant layer for "quick" lookup.
func voxel_at_point(hd: HitData) -> Voxel:
	# Move "into" the surface hit point toward the voxel center
	var corrected_pos: Vector3 = hd.point - hd.normal * (WorldMap.world_settings.voxel_height * 0.5)
	
	var y := int(floor(corrected_pos.y / WorldMap.world_settings.voxel_height))
	var layer = voxel_layers.get(y)
	#print("Attempted select at layer:", y, " | corrected_pos:", corrected_pos)

	if not layer:
		layer = voxel_layers.get(y - 1)
	if not layer:
		return null
	
	# Start from a random voxel (or pick first)
	var current: Voxel = layer.pick_random()
	var current_dist: float = current.world_position.distance_to(corrected_pos)
	var visited: Array[Voxel]
		
	while true:
		var found_better := false
		var neighbors: Array[Voxel] = WorldMap.get_tile_neighbors_planar(current)
		#draw_neighbors(current)
		for n in neighbors:
			if visited.has(n):
				continue
			var dist := n.world_position.distance_to(corrected_pos)
			if dist < current_dist:
				current = n
				current_dist = dist
				found_better = true
		
		visited.append(current)
		
		# stop when no closer neighbor exists
		if not found_better:
			break
	
	#print("Visited: ", visited.size(), " / ", layer.size())
	return current
