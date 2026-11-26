@tool
extends EditorPlugin
## Enabling the plugin adds the Partii autoload (res://addons/partii/partii.gd); disabling removes it.
## Web exports leave the native GDExtension out (it has no web library; the web build uses partii-sdk.js),
## so a web game with the release zip installed logs no "No GDExtension library found" errors.

var _export: EditorExportPlugin

func _enter_tree() -> void:
	_export = _WebSkipsNative.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null

func _enable_plugin() -> void:
	add_autoload_singleton("Partii", "res://addons/partii/partii.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton("Partii")

class _WebSkipsNative extends EditorExportPlugin:
	const EXT := "res://addons/partii/partii.gdextension"
	var _web := false

	func _get_name() -> String:
		return "PartiiWebSkipsNative"

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		_web = "web" in features

	func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
		if not _web:
			return
		if path == EXT or path.begins_with("res://addons/partii/bin/"):
			skip()
		elif path == "res://.godot/extension_list.cfg":
			var keep := PackedStringArray()
			for line in FileAccess.get_file_as_string(path).split("\n"):
				if line.strip_edges() != "" and line.strip_edges() != EXT:
					keep.append(line)
			skip()
			if not keep.is_empty():
				add_file(path, ("\n".join(keep) + "\n").to_utf8_buffer(), false)
