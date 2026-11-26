@tool
extends EditorPlugin
## Enabling the plugin adds the Partii autoload (res://addons/partii/partii.gd); disabling removes it.
## Web exports don't use the native GDExtension (no web library; the web build uses partii-sdk.js).
## Godot lists every .gdextension that the preset's filters let through in the export's
## extension_list.cfg, and export plugins can't change that, so the web preset needs
## `addons/partii/partii.gdextension, addons/partii/bin/*` in its exclude filter. This warns when it's missing.

var _export: EditorExportPlugin

func _enter_tree() -> void:
	_export = _WebNativeCheck.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null

func _enable_plugin() -> void:
	add_autoload_singleton("Partii", "res://addons/partii/partii.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton("Partii")

class _WebNativeCheck extends EditorExportPlugin:
	const EXT := "res://addons/partii/partii.gdextension"
	const FILTER := "addons/partii/partii.gdextension, addons/partii/bin/*"
	var _web := false

	func _get_name() -> String:
		return "PartiiWebNativeCheck"

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		_web = "web" in features
		if not _web or not FileAccess.file_exists(EXT):
			return
		var preset = get_export_preset() if has_method("get_export_preset") else null
		var ex := ""
		if preset and preset.has_method("get_exclude_filter"):
			ex = preset.get_exclude_filter()
		if not ex.contains("partii.gdextension"):
			push_warning("Partii: add \"%s\" to this web preset's \"Filters to exclude files/folders\", or the browser console shows GDExtension load errors at start (the web build doesn't use the native library)." % FILTER)

	func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
		# The native binaries are no use on the web: keep them out even when the filter is missing.
		if _web and path.begins_with("res://addons/partii/bin/"):
			skip()
