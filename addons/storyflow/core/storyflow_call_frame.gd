class_name StoryFlowCallFrame
extends RefCounted

## Path of the calling script.
var script_path: String = ""

## Node ID of the RunScript node to return to.
var return_node_id: String = ""

## Reference to the calling script asset.
var script_asset: StoryFlowScript = null

## The caller's live local-variable records at the time of the call (SHARED,
## not copied — HTML slice semantics: map aliasing established before the call
## must survive it). Safe because the called script reassigns the context's
## local_variables Dictionary rather than mutating this one.
var saved_variables: Dictionary = {}

## Saved flow call stack IDs.
var saved_flow_stack: Array[String] = []
