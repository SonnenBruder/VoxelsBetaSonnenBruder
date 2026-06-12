# Voxel Worldgen Addon

Reusable Godot 4 voxel hex world generation.

## Install

1. Copy `addons/voxel_worldgen` into a Godot project.
2. Enable **Project > Project Settings > Plugins > Voxel Worldgen**.
3. The plugin adds the required `VoxelData` and `WorldMap` autoloads if they are missing.
4. Add a `VoxelWorldGenerator` node or instance `res://addons/voxel_worldgen/world_generator.gd`.
5. Assign a `VoxelWorldPreset` or a `GenerationSettings` resource.
6. Add a `Node3D` named `Chunks` two levels above the generator, or assign `chunks_root` manually.
7. Connect `world_result_ready(result)` for gameplay systems.

The demo scene lives at `res://addons/voxel_worldgen/demo/worldgen_demo.tscn`.
