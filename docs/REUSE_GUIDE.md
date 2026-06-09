# Reusing the Voxel Hex Map Generator

This guide explains how to move generator from this project into future Godot projects with minimal guesswork.

## Scope

Generator builds hex-prism voxel terrain mesh from noise and shape settings.

- Core output: one generated `Chunk` mesh + collision.
- Optional output: villages and prototype units.
- Runtime data written to `WorldMap` singleton (`map_as_dict`, `surface_layer`, settings metadata).

## Architecture at a glance

```mermaid
flowchart TD
    A[WorldGenerator world_gen.gd] --> B[GridMapper]
    B --> C[Array of Voxel positions]
    C --> D[VoxelGenerator]
    D --> E[Chunk mesh + collider]
    D --> F[WorldMap map_as_dict + surface_layer]
                                                                                                   A -->|world_generated| G[ObjectPlacer listener optional]
   A -->|world_generated| H[Interaction tracker listener optional]
   A -->|generation_profile_ready| I[GenerationReportLabel listener optional]
```

## Required files

Copy these files as baseline generator package.

### Core scripts (required)

- `scripts/WorldGen/world_gen.gd`
- `scripts/WorldGen/grid_mapper.gd`
- `scripts/WorldGen/generation_settings.gd`
- `scripts/WorldGen/Voxel/voxel_generator.gd`
- `scripts/WorldGen/Voxel/voxel.gd`
- `scripts/WorldGen/Voxel/chunk.gd`
- `scripts/Global/world.gd`
- `scripts/Global/voxel_data.gd`
- `scripts/hit_data.gd` (used by `Chunk.voxel_at_point`)

### Resources and assets (required)

- At least one `GenerationSettings` resource, for example:
  - `Resources/GenerationSettings/test.tres`
- Material for generated mesh, referenced by `GenerationSettings.material`
- Texture atlas coordinates in `VoxelData.tile_map` must match your atlas layout

### Optional scripts (only if you need gameplay layer)

- `scripts/WorldGen/object_placer.gd`
- `scripts/pathfinder.gd`
- `scripts/interaction.gd`
- `scripts/WorldGen/generation_report_label.gd`
- `scripts/unit.gd`

### Currently unused in runtime generation path

- `scripts/WorldGen/mapping_data.gd`
- `scripts/WorldGen/position_data.gd`

These can stay out of migration unless you plan to use them.

## Required autoloads

Add these singletons in Project Settings > Autoload:

- `VoxelData` -> `res://scripts/Global/voxel_data.gd`
- `WorldMap` -> `res://scripts/Global/world.gd`

`Debugger` autoload is optional for generator itself.

## Scene contract expected by world_gen.gd

`world_gen.gd` now supports injected dependencies for plug-and-play use.

- `chunks_root : Node3D` (required)

Fallback NodePaths are still available:

- `chunks_root_path`

Behavior toggles:

- `generate_on_ready`

Public API for external systems:

- `regenerate_world()`
- `world_generated(chunk, voxel_count)` signal
- `generation_profile_ready(profile)` signal

## Variable reference (exported)

### `world_gen.gd`

- `settings`: `GenerationSettings` resource used for current generation run.
- `chunks_root`: `Node3D` parent receiving generated chunk instances.
- `chunks_root_path`: fallback path used to resolve `chunks_root` if unset.
- `generate_on_ready`: if true, auto-start generation in `_ready()`.

### `object_placer.gd`

- `world_generator`: signal source for `world_generated`.
- `world_generator_path`: fallback path for resolving `world_generator`.
- `auto_connect`: if true, listener auto-connects in `_ready()`.
- `village`: village scene spawned on valid placeable voxels.
- `proto_unit`: unit scene used for starting unit placement.

### `interaction.gd`

- `world_generator`: signal source for initialization after generation.
- `world_generator_path`: fallback path for resolving `world_generator`.
- `auto_connect_world_generator`: auto-connect behavior for generation listener.
- `voxel_cursor_scene`: scene used for voxel cursor visuals.
- `unit_cursor_scene`: scene used for unit cursor visuals.
- `main_camera`: camera used for click raycasting.
- `p_finder`: pathfinder used for reachable-tiles highlighting.
- `selection_indicator`: UI texture swapped between select/build modes.

### `generation_report_label.gd`

- `world_generator`: signal source for generation timing profile updates.
- `world_generator_path`: fallback path for resolving `world_generator`.
- `auto_connect`: if true, listener auto-connects in `_ready()`.
- `seconds_threshold_ms`: threshold for switching total duration display from ms to seconds.

## Migration checklist (recommended order)

1. Copy required scripts and resources into target project.
2. Add autoloads `WorldMap` and `VoxelData`.
3. Create a scene with one node running `world_gen.gd`.
4. Assign `chunks_root` in inspector (or set `chunks_root_path`).
5. Add optional listeners you need:
   - `ObjectPlacer` listening to `world_generated`
   - `Interaction_tracker` listening to `world_generated`
   - `GenerationReportLabel` listening to `generation_profile_ready`
6. Create or copy one `GenerationSettings` resource and assign it to `world_gen.gd`.
7. Set `GenerationSettings.material` and ensure atlas mapping in `VoxelData.tile_map` is valid.
8. Disable gameplay extras first:
   - `spawn_villages_and_units = false`
9. Run generation once, verify mesh and collision.
10. If using villages/units, add `ObjectPlacer` node and connect it to `world_generated` signal (manual or auto-connect).
11. Re-enable optional systems (villages, units, pathfinding) one by one.

## Generation flow details

`world_gen.gd` flow:

1. Resolve dependencies from direct exports or fallback paths.
2. Clear map state and old chunk children.
3. Apply settings and initialize random seed.
4. `GridMapper.calculate_map_positions()` builds full voxel position list by shape.
5. `VoxelGenerator.generate_chunk()`:
   - normalizes noise
   - marks air/solid from `GenerationSettings`
   - builds hex prism mesh with atlas UVs
   - updates `WorldMap` dictionaries
6. Add returned `Chunk` to `chunks_root` and initialize collider/layers.
7. Build generation profile and emit `generation_profile_ready`.
8. Emit `world_generated` signal.
9. Optional listeners react (placement, interaction initialization, UI updates).
10. Generation complete.

## Key GenerationSettings controls

- `map_shape`: `HEXAGONAL`, `RECTANGULAR`, `DIAMOND`, `CIRCLE`
- `radius`: horizontal map size
- `max_height`: voxel stack height per tile
- `noise_height_bias`: blend between noise vs height influence
- `ground_to_air_ratio`: higher value keeps more solid voxels
- `terrace_steps`: erosion-like shaping over neighbors
- `flat_buffer` and `map_edge_buffer`: controls map border trimming
- `voxel_size`, `voxel_height`: world scale
- `material`: mesh material override for generated chunk

## Common pitfalls

### 1) `chunks_root` not assigned

Generator now logs error and aborts if no `chunks_root` can be resolved.

### 2) Listener not connected

If `ObjectPlacer` is present but not connected to `world_generated`, no villages/units spawn even when `spawn_villages_and_units` is true.

Same pattern for `Interaction_tracker` and `GenerationReportLabel`: no signal connection means no initialization/update.

### 3) Atlas mismatch causes wrong textures

`VoxelGenerator` uses fixed atlas constants and `VoxelData.tile_map`. If atlas dimensions, tile size, margin, or stride differ, UVs point to wrong tiles.

## Suggested hardening before reuse

For long-term reuse, consider this small refactor set:

1. Move atlas constants from `voxel_generator.gd` into configurable resource.
2. Add deterministic RNG abstraction instead of global `randi()` for fully reproducible generation sessions.
3. Add generation strategy interface if you want to swap different terrain algorithms behind same `world_gen.gd` node.

This keeps generator portable across projects with different scene trees and art pipelines.
