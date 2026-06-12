extends SceneTree
## Headless tests for the modulo / moduloFloat arithmetic nodes.
##
## Parity contract pinned by the editor's HTML-runtime tests:
##   - Truncated remainder, sign follows the dividend (GDScript's integer %
##     and fmod() both match; posmod/fposmod would not).
##   - Division by zero returns 0 (integer) / 0.0 (float).
##   - A missing inline value2 defaults to 0 / 0.0 and hits the zero guard,
##     so the result is 0 (unlike divide, whose missing value2 defaults to 1).
##
## Run from the repository root (import first to build the class cache):
##   godot --headless --import
##   godot --headless --script res://tests/test_modulo_nodes.gd
## Or: powershell -File tests/run_tests.ps1 -GodotExe <path-to-godot>

const ImporterScript := preload("res://addons/storyflow/editor/storyflow_importer.gd")
const ManagerScript := preload("res://addons/storyflow/core/storyflow_manager.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	await process_frame

	_run_integer_tests()
	_run_float_tests()

	if _failures == 0:
		print("ALL %d CHECKS PASSED" % _checks)
	else:
		print("%d OF %d CHECKS FAILED" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


# =============================================================================
# Integer (modulo)
# =============================================================================

func _run_integer_tests() -> void:
	_run_int_case("modulo 7 % 3", {"value1": 7, "value2": 3}, 1)
	_run_int_case("modulo 10 % 5", {"value1": 10, "value2": 5}, 0)
	_run_int_case("modulo 5 % 0 (zero guard)", {"value1": 5, "value2": 0}, 0)
	_run_int_case("modulo -1 % 3 (sign follows dividend)", {"value1": -1, "value2": 3}, -1)
	_run_int_case("modulo 7 % -3 (sign follows dividend)", {"value1": 7, "value2": -3}, 1)
	_run_int_case("modulo missing value2 defaults to 0", {"value1": 5}, 0)

	# Counter cycling through % 3 (HTML-runtime reference sequence).
	var expected := [0, 1, 2, 0, 1, 2]
	for i in range(6):
		_run_int_case("modulo %d %% 3 cycles" % i, {"value1": i, "value2": 3}, expected[i])


func _run_int_case(case_name: String, values: Dictionary, expected: int) -> void:
	var node := values.duplicate()
	node["type"] = "modulo"
	var variable := {"id": "var1", "name": "result", "type": "integer", "value": 0}
	var captured := _run_graph(case_name, _build_script_json("setInt", "integer", node, variable))
	if captured == null:
		return
	var got := captured.get_int()
	_check("%s: expected %d, got %d" % [case_name, expected, got], got == expected)


# =============================================================================
# Float (moduloFloat)
# =============================================================================

func _run_float_tests() -> void:
	_run_float_case("moduloFloat 5.5 % 2", {"value1": 5.5, "value2": 2.0}, 1.5)
	_run_float_case("moduloFloat 5.5 % 0.0 (zero guard)", {"value1": 5.5, "value2": 0.0}, 0.0)
	_run_float_case("moduloFloat -1.5 % 1.0 (sign follows dividend)", {"value1": -1.5, "value2": 1.0}, -0.5)
	_run_float_case("moduloFloat missing value2 defaults to 0.0", {"value1": 5.5}, 0.0)


func _run_float_case(case_name: String, values: Dictionary, expected: float) -> void:
	var node := values.duplicate()
	node["type"] = "moduloFloat"
	var variable := {"id": "var1", "name": "result", "type": "float", "value": 0.0}
	var captured := _run_graph(case_name, _build_script_json("setFloat", "float", node, variable))
	if captured == null:
		return
	var got := captured.get_float()
	_check("%s: expected %f, got %f" % [case_name, expected, got], is_equal_approx(got, expected))


# =============================================================================
# Helpers
# =============================================================================

## Import the script JSON, run the graph start -> set node -> end, and return
## the StoryFlowVariant the set node stored into the "result" variable.
func _run_graph(case_name: String, script_json: Dictionary) -> StoryFlowVariant:
	var importer := ImporterScript.new()
	var sf_script: StoryFlowScript = importer.import_script(_json_round_trip(script_json))
	_check("%s: script imported" % case_name, sf_script != null)
	if sf_script == null:
		return null
	sf_script.script_path = "test"

	var project := StoryFlowProject.new()
	project.scripts["test"] = sf_script

	var mgr: Node = root.get_node_or_null("StoryFlowRuntime")
	if mgr == null:
		mgr = ManagerScript.new()
		mgr.name = "StoryFlowRuntime"
		root.add_child(mgr)
	mgr.set_project(project)

	var component := StoryFlowComponent.new()
	component.trace_enabled = false
	root.add_child(component)

	var captured: Array = []
	component.variable_changed.connect(func(info: StoryFlowVariableChangeInfo) -> void:
		if info.name == "result":
			captured.append(info.value)
	)

	component.start_dialogue_with_script("test")

	root.remove_child(component)
	component.free()

	_check("%s: variable_changed fired" % case_name, captured.size() > 0)
	if captured.size() == 0:
		return null
	return captured.back()


## Minimal script graph: start(0) -> setInt/setFloat(1) -> end(3), with the
## modulo node (2) wired into the set node's typed input. Inline value1/value2
## sit at the node's top level, exactly as the editor exports them.
func _build_script_json(set_type: String, handle: String, modulo_node: Dictionary, variable: Dictionary) -> Dictionary:
	return {
		"nodes": {
			"0": {"type": "start"},
			"1": {"type": set_type, "data": {"variable": "var1", "isGlobal": false}},
			"2": modulo_node,
			"3": {"type": "end"},
		},
		"connections": [
			{"id": "c1", "source": "0", "target": "1", "sourceHandle": "source-0-", "targetHandle": "target-1-"},
			{"id": "c2", "source": "2", "target": "1", "sourceHandle": "source-2-%s-2" % handle, "targetHandle": "target-1-%s-1" % handle},
			{"id": "c3", "source": "1", "target": "3", "sourceHandle": "source-1-1", "targetHandle": "target-3-"},
		],
		"variables": {"var1": variable},
	}


## Serialize and reparse so fixtures arrive exactly as real JSON files do
## (string keys, numbers as floats, no GDScript-only types).
func _json_round_trip(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("  PASS: %s" % label)
	else:
		_failures += 1
		printerr("  FAIL: %s" % label)
