@tool
extends EditorPlugin
## Enabling the plugin adds the Partii autoload (res://addons/partii/partii.gd); disabling removes it.

func _enable_plugin() -> void:
	add_autoload_singleton("Partii", "res://addons/partii/partii.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton("Partii")
