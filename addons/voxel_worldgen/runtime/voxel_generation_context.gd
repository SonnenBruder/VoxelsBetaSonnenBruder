extends RefCounted
class_name VoxelGenerationContext

var settings: GenerationSettings
var requested_seed: int
var seed_used: int
var random: RandomNumberGenerator
var atlas_settings: Resource
var interval: Dictionary = {}
var metadata: Dictionary = {}
