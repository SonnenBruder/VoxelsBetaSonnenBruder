extends RichTextLabel
class_name GenerationReportLabel

@export_category("Dependencies")
## World generator that emits generation_profile_ready signal.
@export var world_generator : Node
## Fallback path for resolving world_generator reference.
@export var world_generator_path: NodePath = ^"../../../Builder/WorldGenerator"
## Auto-connect signal listener during _ready.
@export var auto_connect := true

@export_category("Formatting")
## Threshold where total duration switches from ms display to s display.
@export var seconds_threshold_ms := 1000.0


func _ready() -> void:
	if auto_connect:
		connect_to_world_generator()


func connect_to_world_generator() -> void:
	resolve_dependencies()
	if world_generator == null:
		push_warning("GenerationReportLabel: world_generator missing")
		return
	if not world_generator.has_signal("generation_profile_ready"):
		push_warning("GenerationReportLabel: world_generator has no generation_profile_ready signal")
		return
	var callback := Callable(self, "_on_generation_profile_ready")
	if not world_generator.is_connected("generation_profile_ready", callback):
		world_generator.connect("generation_profile_ready", callback)


func resolve_dependencies() -> void:
	if world_generator == null and not world_generator_path.is_empty():
		world_generator = get_node_or_null(world_generator_path)


func _on_generation_profile_ready(profile: Dictionary) -> void:
	text = format_profile(profile)


func format_profile(profile: Dictionary) -> String:
	var lines = profile.get("lines", [])
	var output := ""
	for line in lines:
		var label = str(line.get("label", "Step"))
		var duration_ms = snappedf(float(line.get("duration_ms", 0.0)), 0.01)
		output += "[b]" + label + "[/b][i]" + str(duration_ms) + "ms\n[/i]"

	var total_ms = float(profile.get("total_ms", 0.0))
	var unit := "ms"
	var display_total = total_ms
	if total_ms >= seconds_threshold_ms:
		unit = "s"
		display_total = total_ms * 0.001
	output += "[b]Total completion time: [/b][i]" + str(snappedf(display_total, 0.01)) + unit + "[/i]"
	return output
