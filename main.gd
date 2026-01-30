extends Node3D

enum TestMode { FOV, OVERLAP }

var xr_interface: XRInterface
@onready var xr_origin := $XROrigin3D
@onready var camera := $XROrigin3D/XRCamera3D
@onready var left_controller := $XROrigin3D/LeftController
@onready var right_controller := $XROrigin3D/RightController

# Frames
@onready var fov_frame := $XROrigin3D/XRCamera3D/FOVFrame
@onready var overlap_frame := $XROrigin3D/XRCamera3D/OverlapFrame
@onready var overlap_left_cyan: MeshInstance3D = $XROrigin3D/XRCamera3D/OverlapFrame/LeftEdgeCyan
@onready var overlap_left_magenta: MeshInstance3D = $XROrigin3D/XRCamera3D/OverlapFrame/LeftEdgeMagenta
@onready var overlap_right_cyan: MeshInstance3D = $XROrigin3D/XRCamera3D/OverlapFrame/RightEdgeCyan
@onready var overlap_right_magenta: MeshInstance3D = $XROrigin3D/XRCamera3D/OverlapFrame/RightEdgeMagenta

# Stats
@onready var stats_container := $XROrigin3D/XRCamera3D/StatsContainer
@onready var stats_label: Label3D = $XROrigin3D/XRCamera3D/StatsContainer/StatsLabel
@onready var offset_label: Label3D = $XROrigin3D/XRCamera3D/StatsContainer/OffsetLabel

# Current mode
var current_mode: TestMode = TestMode.FOV

# FOV test settings (preserved when switching modes)
var fov_half_width := 0.15
var fov_half_height := 0.10
var fov_offset_v := 0.0

# Overlap test settings (preserved when switching modes)
var overlap_half_width := 0.15
var overlap_half_height := 0.10
var overlap_offset_v := 0.0

# Active settings (point to current mode's values)
var rect_half_width := 0.15
var rect_half_height := 0.10
var rect_distance := 0.5
var offset_v := 0.0

var offset_description_offset := 0.45

@export var resize_speed := 0.15
@export var offset_speed := 15.0
@export var move_speed := 2.0

const CAPSULE_RADIUS := 0.004

# Button state for edge detection
var _a_button_was_pressed := false

func _ready() -> void:
	print("FOV Tester loaded")
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.initialize():
		print("OpenXR initialized")
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# Give each FOV capsule its own unique mesh for independent sizing
	_duplicate_frame_meshes(fov_frame)
	# Overlap lines - duplicate meshes but preserve materials
	for line in [overlap_left_cyan, overlap_left_magenta, overlap_right_cyan, overlap_right_magenta]:
		var mat = line.material_override
		line.mesh = line.mesh.duplicate()
		line.material_override = mat

	_apply_mode()
	_update_active_frame()
	_update_stats()

func _duplicate_frame_meshes(frame: Node3D) -> void:
	for child_name in ["Top", "Bottom", "Left", "Right"]:
		var child: MeshInstance3D = frame.get_node(child_name)
		child.mesh = child.mesh.duplicate()

func _process(delta: float) -> void:
	var left_stick := Vector2.ZERO
	var right_stick := Vector2.ZERO
	var left_grip := 0.0
	var right_grip := 0.0
	var a_button := false

	var left_tracker := XRServer.get_tracker("left_hand")
	var right_tracker := XRServer.get_tracker("right_hand")

	if left_tracker:
		var primary = left_tracker.get_input("primary")
		var grip = left_tracker.get_input("grip")
		if primary != null:
			left_stick = primary
		if grip != null:
			left_grip = grip
	if right_tracker:
		var primary = right_tracker.get_input("primary")
		var grip = right_tracker.get_input("grip")
		var ax = right_tracker.get_input("ax_button")
		if primary != null:
			right_stick = primary
		if grip != null:
			right_grip = grip
		if ax != null:
			a_button = ax

	# A button press detection (edge triggered) - cycle modes
	if a_button and not _a_button_was_pressed:
		_cycle_mode()
	_a_button_was_pressed = a_button

	# Right grip held: joystick Y controls vertical offset
	# Otherwise: joystick controls rectangle size
	var size_changed := false
	var offset_changed := false

	if right_grip > 0.5:
		if abs(right_stick.y) > 0.1:
			offset_v -= deg_to_rad(right_stick.y * offset_speed * delta)
			offset_changed = true
	else:
		var abs_x: float = absf(right_stick.x)
		var abs_y: float = absf(right_stick.y)
		var both_high: bool = abs_x > 0.7 and abs_y > 0.7

		if both_high:
			rect_half_width += right_stick.x * resize_speed * delta
			rect_half_width = clamp(rect_half_width, 0.02, 1.0)
			rect_half_height += right_stick.y * resize_speed * delta
			rect_half_height = clamp(rect_half_height, 0.02, 1.0)
			size_changed = true
		elif abs_x > 0.1 and abs_x >= abs_y:
			rect_half_width += right_stick.x * resize_speed * delta
			rect_half_width = clamp(rect_half_width, 0.02, 1.0)
			size_changed = true
		elif abs_y > 0.1:
			rect_half_height += right_stick.y * resize_speed * delta
			rect_half_height = clamp(rect_half_height, 0.02, 1.0)
			size_changed = true

	if size_changed:
		_update_active_frame()
		_update_stats()
	elif offset_changed:
		_update_frame_rotation()
		_update_stats()

	# Left stick locomotion
	var forward: Vector3 = camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	var right: Vector3 = camera.global_transform.basis.x
	right.y = 0
	right = right.normalized()

	var move := Vector3.ZERO
	if left_grip > 0.5:
		move.y = left_stick.y
	else:
		move += forward * -left_stick.y
	move += right * left_stick.x
	xr_origin.global_position += move * move_speed * delta

func _cycle_mode() -> void:
	# Save current mode's settings
	_save_current_mode_settings()

	# Cycle to next mode
	if current_mode == TestMode.FOV:
		current_mode = TestMode.OVERLAP
	else:
		current_mode = TestMode.FOV

	# Load new mode's settings
	_load_current_mode_settings()
	_apply_mode()
	_update_active_frame()
	_update_stats()

func _save_current_mode_settings() -> void:
	if current_mode == TestMode.FOV:
		fov_half_width = rect_half_width
		fov_half_height = rect_half_height
		fov_offset_v = offset_v
	else:
		overlap_half_width = rect_half_width
		overlap_half_height = rect_half_height
		overlap_offset_v = offset_v

func _load_current_mode_settings() -> void:
	if current_mode == TestMode.FOV:
		rect_half_width = fov_half_width
		rect_half_height = fov_half_height
		offset_v = fov_offset_v
	else:
		rect_half_width = overlap_half_width
		rect_half_height = overlap_half_height
		offset_v = overlap_offset_v

func _apply_mode() -> void:
	fov_frame.visible = (current_mode == TestMode.FOV)
	overlap_frame.visible = (current_mode == TestMode.OVERLAP)

func _update_active_frame() -> void:
	if current_mode == TestMode.FOV:
		_update_frame(fov_frame)
	else:
		_update_overlap_lines()

func _update_frame(frame: Node3D) -> void:
	var top: MeshInstance3D = frame.get_node("Top")
	var bottom: MeshInstance3D = frame.get_node("Bottom")
	var left: MeshInstance3D = frame.get_node("Left")
	var right: MeshInstance3D = frame.get_node("Right")

	var h_length := 2.0 * (rect_half_width + CAPSULE_RADIUS)
	var v_length := 2.0 * (rect_half_height + CAPSULE_RADIUS)

	top.position = Vector3(0, rect_half_height, -rect_distance)
	top.rotation_degrees = Vector3(0, 0, 90)
	_set_capsule_length(top, h_length)

	bottom.position = Vector3(0, -rect_half_height, -rect_distance)
	bottom.rotation_degrees = Vector3(0, 0, 90)
	_set_capsule_length(bottom, h_length)

	left.position = Vector3(-rect_half_width, 0, -rect_distance)
	left.rotation_degrees = Vector3.ZERO
	_set_capsule_length(left, v_length)

	right.position = Vector3(rect_half_width, 0, -rect_distance)
	right.rotation_degrees = Vector3.ZERO
	_set_capsule_length(right, v_length)

	_update_frame_rotation()

func _update_overlap_lines() -> void:
	# Four vertical lines - cyan and magenta at each edge (left and right)
	# Both colors at same position - where both visible = binocular overlap
	var v_length := 2.0 * (rect_half_height + CAPSULE_RADIUS)

	# Left edge - both cyan (left eye) and magenta (right eye)
	overlap_left_cyan.position = Vector3(-rect_half_width, 0, -rect_distance)
	overlap_left_magenta.position = Vector3(-rect_half_width, 0, -rect_distance)
	_set_capsule_length(overlap_left_cyan, v_length)
	_set_capsule_length(overlap_left_magenta, v_length)

	# Right edge - both cyan (left eye) and magenta (right eye)
	overlap_right_cyan.position = Vector3(rect_half_width, 0, -rect_distance)
	overlap_right_magenta.position = Vector3(rect_half_width, 0, -rect_distance)
	_set_capsule_length(overlap_right_cyan, v_length)
	_set_capsule_length(overlap_right_magenta, v_length)

	_update_frame_rotation()

func _update_frame_rotation() -> void:
	if current_mode == TestMode.FOV:
		fov_frame.rotation = Vector3(-offset_v, 0, 0)
	else:
		overlap_frame.rotation = Vector3(-offset_v, 0, 0)

func _set_capsule_length(node: MeshInstance3D, length: float) -> void:
	var mesh: CapsuleMesh = node.mesh
	mesh.height = length

func _update_stats() -> void:
	var h_fov_rad := 2.0 * atan(rect_half_width / rect_distance)
	var v_fov_rad := 2.0 * atan(rect_half_height / rect_distance)
	var diagonal_half := sqrt(rect_half_width * rect_half_width + rect_half_height * rect_half_height)
	var d_fov_rad := 2.0 * atan(diagonal_half / rect_distance)

	var h_fov_deg := rad_to_deg(h_fov_rad)
	var v_fov_deg := rad_to_deg(v_fov_rad)
	var d_fov_deg := rad_to_deg(d_fov_rad)

	var text: String
	if current_mode == TestMode.FOV:
		text = "H: %.1f°\nV: %.1f°\nD: %.1f°" % [h_fov_deg, v_fov_deg, d_fov_deg]
	else:
		# In overlap mode, h_fov represents the overlap (distance between lines)
		text = "OVERLAP\nH: %.1f°\nV: %.1f°" % [h_fov_deg, v_fov_deg]

	stats_label.text = text

	# Offset shown as smaller parenthetical after V line
	var v_offset_deg := rad_to_deg(-offset_v)
	if abs(v_offset_deg) > 0.1:
		offset_label.text = "(%.1f° offset)" % v_offset_deg
		offset_label.visible = true

		var v_line := "V: %.1f° " % v_fov_deg
		var char_count := v_line.length()
		var pixel := stats_label.pixel_size
		var char_width := stats_label.font_size * pixel * offset_description_offset
		var x_pos := char_count * char_width

		# Adjust Y position based on mode (V line is on different row)
		var line_height := stats_label.font_size * pixel
		var y_offset := 0.0 if current_mode == TestMode.FOV else -line_height
		offset_label.position = Vector3(x_pos, y_offset, 0)
	else:
		offset_label.text = ""
		offset_label.visible = false

	# Center the container
	var longest_line := "OVERLAP TEST" if current_mode == TestMode.OVERLAP else "V: %.1f°" % v_fov_deg
	var pixel := stats_label.pixel_size
	var char_width := stats_label.font_size * pixel * offset_description_offset
	var main_width := longest_line.length() * char_width
	stats_container.position.x = -main_width / 2.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reload"):
		print("Reloading...")
		get_tree().reload_current_scene()
