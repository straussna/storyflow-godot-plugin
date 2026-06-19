extends SceneTree
## Headless tests for the typed map get/set public API on StoryFlowComponent.
##
## Mirrors test_array_variable_setters.gd. The accessors collapse the
## key-type x value-type space to native Godot types: keys are either int
## (integer keyType) or String (string/enum keyType); values are bool, int,
## float, or String (string/enum/image/audio/character all stored as String).
## That yields 8 set/get signatures, each a Dictionary round trip.
##
## Like the array API: string and enum VALUES route through the string table,
## image/audio/character values pass through raw, KEYS are always raw, and a
## wrong-type / missing variable pushes a warning and yields an empty
## Dictionary (getters) or a no-op (setters). Godot Dictionaries preserve
## insertion order, so order is asserted directly off keys().
##
## Run from the repository root (import first to build the class cache):
##   godot --headless --import
##   godot --headless --script res://tests/test_map_variable_accessors.gd
## Or: powershell -File tests/run_tests.ps1 -GodotExe <path-to-godot>

const ManagerScript := preload("res://addons/storyflow/core/storyflow_manager.gd")

var _checks: int = 0
var _failures: int = 0

var _manager: Node = null
var _component: StoryFlowComponent = null


func _initialize() -> void:
	await process_frame

	_setup()
	_run_string_key_value_tests()
	_run_int_key_tests()
	_run_value_resolution_tests()
	_run_asset_passthrough_tests()
	_run_insertion_order_test()
	_run_guard_tests()

	if _failures == 0:
		print("ALL %d CHECKS PASSED" % _checks)
	else:
		print("%d OF %d CHECKS FAILED" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("  PASS: %s" % label)
	else:
		_failures += 1
		print("  FAIL: %s" % label)


func _setup() -> void:
	_manager = ManagerScript.new()
	_manager.name = "StoryFlowRuntime"
	root.add_child(_manager)

	_component = StoryFlowComponent.new()
	root.add_child(_component)

	var T := StoryFlowTypes.VariableType
	# string-keyed maps, one per value family
	_add_global_map("m_s_bool", "FlagsByName", T.STRING, T.BOOLEAN)
	_add_global_map("m_s_int", "ScoresByName", T.STRING, T.INTEGER)
	_add_global_map("m_s_float", "WeightsByName", T.STRING, T.FLOAT)
	_add_global_map("m_s_str", "LabelsByName", T.STRING, T.STRING)
	_add_global_map("m_s_enum", "MoodsByName", T.STRING, T.ENUM)
	_add_global_map("m_s_img", "PortraitsByName", T.STRING, T.IMAGE)
	_add_global_map("m_s_audio", "ThemesByName", T.STRING, T.AUDIO)
	_add_global_map("m_s_char", "CastByName", T.STRING, T.CHARACTER)
	# enum-keyed map (keys stored as String, so it is a string-key signature)
	_add_global_map("m_e_int", "ScoresByMood", T.ENUM, T.INTEGER)
	# int-keyed maps, one per value family
	_add_global_map("m_i_bool", "FlagsById", T.INTEGER, T.BOOLEAN)
	_add_global_map("m_i_int", "ScoresById", T.INTEGER, T.INTEGER)
	_add_global_map("m_i_float", "WeightsById", T.INTEGER, T.FLOAT)
	_add_global_map("m_i_str", "LabelsById", T.INTEGER, T.STRING)
	# a non-map and a wrong-family map for the guard tests
	_add_global_array("a_str", "PlainArray", T.STRING)


func _add_global_map(id: String, name: String, key_type: StoryFlowTypes.VariableType, value_type: StoryFlowTypes.VariableType) -> void:
	_manager._global_variables[id] = {
		"id": id,
		"name": name,
		"type": StoryFlowTypes.VariableType.MAP,
		"value": StoryFlowVariant.from_map({}),
		"is_array": false,
		"enum_values": [],
		"key_type": key_type,
		"value_type": value_type,
		"key_enum_values": [],
		"value_enum_values": [],
	}


func _add_global_array(id: String, name: String, type: StoryFlowTypes.VariableType) -> void:
	_manager._global_variables[id] = {
		"id": id,
		"name": name,
		"type": type,
		"value": StoryFlowVariant.new(),
		"is_array": true,
		"enum_values": [],
	}


## Read the raw stored map (key -> StoryFlowVariant) straight out of storage.
func _stored_map(id: String) -> Dictionary:
	var value = _manager._global_variables[id].get("value")
	return value.get_map() if value is StoryFlowVariant else {}


func _run_string_key_value_tests() -> void:
	# bool values, string keys
	_component.set_string_to_bool_map("FlagsByName", {"a": true, "b": false})
	var stored := _stored_map("m_s_bool")
	_check("s->bool: two entries stored", stored.size() == 2)
	if stored.size() == 2:
		_check("s->bool: stored value is variant", stored["a"] is StoryFlowVariant)
		_check("s->bool: stored a == true", stored["a"].get_bool() == true)
	var got_b := _component.get_string_to_bool_map("FlagsByName")
	_check("s->bool: get returns 2", got_b.size() == 2)
	_check("s->bool: get a == true", got_b.get("a") == true)
	_check("s->bool: get b == false", got_b.get("b") == false)

	# int values, string keys
	_component.set_string_to_int_map("ScoresByName", {"alice": 10, "bob": 20})
	var got_i := _component.get_string_to_int_map("ScoresByName")
	_check("s->int: get returns 2", got_i.size() == 2)
	_check("s->int: get alice == 10", got_i.get("alice") == 10)
	_check("s->int: value is native int", typeof(got_i.get("bob")) == TYPE_INT)

	# float values, string keys
	_component.set_string_to_float_map("WeightsByName", {"x": 0.5, "y": 2.25})
	var got_f := _component.get_string_to_float_map("WeightsByName")
	_check("s->float: get returns 2", got_f.size() == 2)
	_check("s->float: get y approx 2.25", is_equal_approx(got_f.get("y"), 2.25))

	# string values, string keys
	_component.set_string_to_string_map("LabelsByName", {"k1": "hello", "k2": "world"})
	var got_s := _component.get_string_to_string_map("LabelsByName")
	_check("s->str: get returns 2", got_s.size() == 2)
	_check("s->str: value is native string", typeof(got_s.get("k1")) == TYPE_STRING)

	# overwrite replaces, empty clears
	_component.set_string_to_int_map("ScoresByName", {"solo": 1})
	_check("s->int: overwrite leaves one", _stored_map("m_s_int").size() == 1)
	_component.set_string_to_int_map("ScoresByName", {})
	_check("s->int: empty write clears", _stored_map("m_s_int").size() == 0)


func _run_int_key_tests() -> void:
	_component.set_int_to_bool_map("FlagsById", {1: true, 2: false})
	var got_b := _component.get_int_to_bool_map("FlagsById")
	_check("i->bool: get returns 2", got_b.size() == 2)
	_check("i->bool: key is native int", typeof(got_b.keys()[0]) == TYPE_INT)
	_check("i->bool: get 1 == true", got_b.get(1) == true)

	_component.set_int_to_int_map("ScoresById", {100: 7, 200: 9})
	var got_i := _component.get_int_to_int_map("ScoresById")
	_check("i->int: get returns 2", got_i.size() == 2)
	_check("i->int: get 200 == 9", got_i.get(200) == 9)

	_component.set_int_to_float_map("WeightsById", {1: 1.5})
	var got_f := _component.get_int_to_float_map("WeightsById")
	_check("i->float: get 1 approx 1.5", is_equal_approx(got_f.get(1), 1.5))

	_component.set_int_to_string_map("LabelsById", {5: "five", 6: "six"})
	var got_s := _component.get_int_to_string_map("LabelsById")
	_check("i->str: get returns 2", got_s.size() == 2)
	_check("i->str: get 5 == five", got_s.get(5) == "five")
	_check("i->str: key native int", typeof(got_s.keys()[0]) == TYPE_INT)


func _run_value_resolution_tests() -> void:
	# Outside dialogue, _resolve_string falls back to the project string table,
	# which is absent here, so unknown keys resolve to themselves. The contract
	# we verify is that the VALUE is routed through the string-table resolver
	# at all (the variant comes back STRING-typed and as a native String),
	# matching get_array_variable / get_map_variable behavior.
	_component.set_string_to_string_map("LabelsByName", {"greeting": "string_key_abc"})
	var got_s := _component.get_string_to_string_map("LabelsByName")
	_check("resolve: string value present", got_s.has("greeting"))
	_check("resolve: string value is String", typeof(got_s.get("greeting")) == TYPE_STRING)

	# enum value type also resolves through the string table and returns String
	_component.set_string_to_string_map("MoodsByName", {"npc": "enum_key_xyz"})
	var got_e := _component.get_string_to_string_map("MoodsByName")
	_check("resolve: enum-valued map returns String", typeof(got_e.get("npc")) == TYPE_STRING)
	# stored variant should carry ENUM type for an enum-value map
	var raw := _stored_map("m_s_enum")
	_check("resolve: enum value stored as ENUM variant", raw["npc"].type == StoryFlowTypes.VariableType.ENUM)

	# enum-keyed map is accepted by the string-key signature; keys raw
	_component.set_string_to_int_map("ScoresByMood", {"happy": 3, "sad": 1})
	var got_ek := _component.get_string_to_int_map("ScoresByMood")
	_check("resolve: enum-key map returns 2", got_ek.size() == 2)
	_check("resolve: enum key raw string", got_ek.get("happy") == 3)


func _run_asset_passthrough_tests() -> void:
	# image / audio / character values are returned RAW (asset keys / paths),
	# never routed through the string table.
	_component.set_string_to_string_map("PortraitsByName", {"hero": "asset_img_42"})
	var got_img := _component.get_string_to_string_map("PortraitsByName")
	_check("asset: image value raw", got_img.get("hero") == "asset_img_42")

	_component.set_string_to_string_map("ThemesByName", {"battle": "asset_audio_7"})
	var got_au := _component.get_string_to_string_map("ThemesByName")
	_check("asset: audio value raw", got_au.get("battle") == "asset_audio_7")

	_component.set_string_to_string_map("CastByName", {"lead": "characters/elder"})
	var got_ch := _component.get_string_to_string_map("CastByName")
	_check("asset: character value raw", got_ch.get("lead") == "characters/elder")
	# stored variant type matches the variable's declared value_type family
	var raw := _stored_map("m_s_char")
	_check("asset: character value stored as STRING variant", raw["lead"].type == StoryFlowTypes.VariableType.STRING)


func _run_insertion_order_test() -> void:
	# Insertion order must survive the round trip (Dictionary preserves it).
	_component.set_string_to_int_map("ScoresByName", {"zeta": 1, "alpha": 2, "mid": 3})
	var got := _component.get_string_to_int_map("ScoresByName")
	var keys := got.keys()
	_check("order: three keys", keys.size() == 3)
	if keys.size() == 3:
		_check("order: key 0 zeta", keys[0] == "zeta")
		_check("order: key 1 alpha", keys[1] == "alpha")
		_check("order: key 2 mid", keys[2] == "mid")

	_component.set_int_to_string_map("LabelsById", {30: "c", 10: "a", 20: "b"})
	var got2 := _component.get_int_to_string_map("LabelsById")
	var keys2 := got2.keys()
	_check("order: int keys preserved", keys2.size() == 3 and keys2[0] == 30 and keys2[1] == 10 and keys2[2] == 20)


func _run_guard_tests() -> void:
	# Wrong value family: m_s_int is string->int; ask for string->bool.
	_component.set_string_to_int_map("ScoresByName", {"a": 5})
	var wrong_val := _component.get_string_to_bool_map("ScoresByName")
	_check("guard: wrong value family -> empty", wrong_val.is_empty())

	# Wrong key family: m_i_int is int->int; ask for string->int.
	_component.set_int_to_int_map("ScoresById", {1: 5})
	var wrong_key := _component.get_string_to_int_map("ScoresById")
	_check("guard: wrong key family -> empty", wrong_key.is_empty())

	# Non-map variable -> empty
	var not_map := _component.get_string_to_int_map("PlainArray")
	_check("guard: non-map variable -> empty", not_map.is_empty())

	# Missing variable -> empty, and setter is a no-op (no variable created)
	var count_before: int = _manager._global_variables.size()
	var missing := _component.get_string_to_int_map("DoesNotExist")
	_check("guard: missing getter -> empty", missing.is_empty())
	_component.set_string_to_int_map("DoesNotExist", {"x": 1})
	_check("guard: missing setter creates nothing", _manager._global_variables.size() == count_before)
	_check("guard: no 'DoesNotExist' entry", not _manager._global_variables.has("DoesNotExist"))

	# Wrong-family setter is a no-op: setting string->bool onto an int->int map
	# must not mutate the stored map.
	_component.set_int_to_int_map("ScoresById", {1: 5})
	_component.set_string_to_bool_map("ScoresById", {"a": true})
	var still := _stored_map("m_i_int")
	_check("guard: wrong-family setter no-op", still.size() == 1 and still.get(1) != null and still[1].get_int() == 5)
