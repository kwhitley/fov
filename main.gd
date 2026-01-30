extends Node3D

var xr_interface: XRInterface
@onready var xr_origin := $XROrigin3D
@onready var camera := $XROrigin3D/XRCamera3D
@onready var left_controller := $XROrigin3D/LeftController
@onready var right_controller := $XROrigin3D/RightController

# FOV rectangle (attached to camera)
@onready var fov_frame := $XROrigin3D/XRCamera3D/FOVFrame
@onready var stats_container := $XROrigin3D/XRCamera3D/StatsContainer
@onready var stats_label: Label3D = $XROrigin3D/XRCamera3D/StatsContainer/StatsLabel
@onready var offset_label: Label3D = $XROrigin3D/XRCamera3D/StatsContainer/OffsetLabel

# Rectangle dimensions (half-widths for easier math)
var rect_half_width := 0.15  # meters
var rect_half_height := 0.10  # meters
var rect_distance := 0.5  # distance from camera in meters

# Rotational offset (in radians) - vertical only
var offset_v := 0.0  # vertical (pitch)
var offset_description_offset := 0.45

@export var resize_speed := 0.15  # meters per second
@export var offset_speed := 15.0  # degrees per second (slower for precision)
@export var move_speed := 2.0

# Capsule radius for corner calculation
const CAPSULE_RADIUS := 0.004

func _ready() -> void:
	print("FOV Tester loaded")
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.initialize():
		print("OpenXR initialized")
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# Give each capsule its own unique mesh so we can size them independently
	for child_name in ["Top", "Bottom", "Left", "Right"]:
		var child: MeshInstance3D = fov_frame.get_node(child_name)
		child.mesh = child.mesh.duplicate()

	_update_fov_frame()
	_update_stats()

func _process(delta: float) -> void:
	var left_stick := Vector2.ZERO
	var right_stick := Vector2.ZERO
	var left_grip := 0.0
	var right_grip := 0.0

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
		if primary != null:
			right_stick = primary
		if grip != null:
			right_grip = grip

	# Right grip held: joystick Y controls vertical offset
	# Otherwise: joystick controls rectangle size
	var size_changed := false
	var offset_changed := false

	if right_grip > 0.5:
		# Offset mode (vertical only) - reversed so joystick up = frame up
		if abs(right_stick.y) > 0.1:
			offset_v -= deg_to_rad(right_stick.y * offset_speed * delta)
			offset_changed = true
	else:
		# Resize mode
		if abs(right_stick.x) > 0.1:
			rect_half_width += right_stick.x * resize_speed * delta
			rect_half_width = clamp(rect_half_width, 0.02, 1.0)
			size_changed = true
		if abs(right_stick.y) > 0.1:
			rect_half_height += right_stick.y * resize_speed * delta
			rect_half_height = clamp(rect_half_height, 0.02, 1.0)
			size_changed = true

	if size_changed:
		_update_fov_frame()
		_update_stats()
	elif offset_changed:
		_update_fov_frame_rotation()
		_update_stats()

	# Left stick locomotion (relative to head direction)
	var forward: Vector3 = camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	var right: Vector3 = camera.global_transform.basis.x
	right.y = 0
	right = right.normalized()

	var move := Vector3.ZERO

	# Grip held: left stick Y becomes vertical movement
	if left_grip > 0.5:
		move.y = left_stick.y
	else:
		move += forward * -left_stick.y

	move += right * left_stick.x

	xr_origin.global_position += move * move_speed * delta

func _update_fov_frame() -> void:
	"""Update the capsule positions and sizes to form the rectangle."""
	var top: MeshInstance3D = fov_frame.get_node("Top")
	var bottom: MeshInstance3D = fov_frame.get_node("Bottom")
	var left: MeshInstance3D = fov_frame.get_node("Left")
	var right: MeshInstance3D = fov_frame.get_node("Right")

	# Capsule height formula: height = 2 * (half_extent + radius)
	# This makes the sphere centers land exactly at the corners
	var h_length := 2.0 * (rect_half_width + CAPSULE_RADIUS)
	var v_length := 2.0 * (rect_half_height + CAPSULE_RADIUS)

	# Horizontal bars (top and bottom) - rotated 90° to lie horizontal
	top.position = Vector3(0, rect_half_height, -rect_distance)
	top.rotation_degrees = Vector3(0, 0, 90)
	_set_capsule_length(top, h_length)

	bottom.position = Vector3(0, -rect_half_height, -rect_distance)
	bottom.rotation_degrees = Vector3(0, 0, 90)
	_set_capsule_length(bottom, h_length)

	# Vertical bars (left and right) - default orientation
	left.position = Vector3(-rect_half_width, 0, -rect_distance)
	left.rotation_degrees = Vector3.ZERO
	_set_capsule_length(left, v_length)

	right.position = Vector3(rect_half_width, 0, -rect_distance)
	right.rotation_degrees = Vector3.ZERO
	_set_capsule_length(right, v_length)

	_update_fov_frame_rotation()

func _update_fov_frame_rotation() -> void:
	"""Apply rotational offset to the FOV frame."""
	# Rotation is applied as pitch (X) only - vertical offset
	fov_frame.rotation = Vector3(-offset_v, 0, 0)

func _set_capsule_length(node: MeshInstance3D, length: float) -> void:
	"""Set the capsule mesh height (length along its axis)."""
	var mesh: CapsuleMesh = node.mesh
	mesh.height = length

func _update_stats() -> void:
	"""Calculate and display FOV based on rectangle size and distance."""
	# FOV = 2 * atan(half_size / distance)
	var h_fov_rad := 2.0 * atan(rect_half_width / rect_distance)
	var v_fov_rad := 2.0 * atan(rect_half_height / rect_distance)

	# Diagonal FOV using the corner distance
	var diagonal_half := sqrt(rect_half_width * rect_half_width + rect_half_height * rect_half_height)
	var d_fov_rad := 2.0 * atan(diagonal_half / rect_distance)

	var h_fov_deg := rad_to_deg(h_fov_rad)
	var v_fov_deg := rad_to_deg(v_fov_rad)
	var d_fov_deg := rad_to_deg(d_fov_rad)

	# Main stats text (left-aligned)
	var text := "H: %.1f°\nV: %.1f°\nD: %.1f°" % [h_fov_deg, v_fov_deg, d_fov_deg]
	stats_label.text = text

	# Offset shown as smaller parenthetical after V line
	# Negative offset = aiming down, positive = aiming up
	var v_offset_deg := rad_to_deg(-offset_v)
	if abs(v_offset_deg) > 0.1:
		offset_label.text = "(%.1f° offset)" % v_offset_deg
		offset_label.visible = true

		# Position after the V text - calculate based on actual string length
		var v_line := "V: %.1f° " % v_fov_deg  # include trailing space
		var char_count := v_line.length()
		var pixel := stats_label.pixel_size
		var char_width := stats_label.font_size * pixel * offset_description_offset  # approximate char width
		var x_pos := char_count * char_width

		# Vertically centered with the V line (y=0)
		offset_label.position = Vector3(x_pos, 0, 0)
	else:
		offset_label.text = ""
		offset_label.visible = false

	# Center the container based on main stats only
	var longest_line := "V: %.1f°" % v_fov_deg
	var pixel := stats_label.pixel_size
	var char_width := stats_label.font_size * pixel * offset_description_offset
	var main_width := longest_line.length() * char_width
	stats_container.position.x = -main_width / 2.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reload"):
		print("Reloading...")
		get_tree().reload_current_scene()
