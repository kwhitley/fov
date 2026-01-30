extends Node3D

var xr_interface: XRInterface
@onready var xr_origin := $XROrigin3D
@onready var camera := $XROrigin3D/XRCamera3D
@onready var left_controller := $XROrigin3D/LeftController
@onready var right_controller := $XROrigin3D/RightController

# FOV rectangle (attached to camera)
@onready var fov_frame := $XROrigin3D/XRCamera3D/FOVFrame
@onready var stats_label := $XROrigin3D/XRCamera3D/StatsLabel

# Rectangle dimensions (half-widths for easier math)
var rect_half_width := 0.15  # meters
var rect_half_height := 0.10  # meters
var rect_distance := 0.5  # distance from camera in meters

@export var resize_speed := 0.15  # meters per second
@export var move_speed := 2.0
@export var turn_speed := 90.0

func _ready() -> void:
	print("FOV Tester loaded")
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.initialize():
		print("OpenXR initialized")
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	_update_fov_frame()
	_update_stats()

func _process(delta: float) -> void:
	var left_stick := Vector2.ZERO
	var right_stick := Vector2.ZERO
	var left_grip := 0.0

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
		if primary != null:
			right_stick = primary

	# Right stick controls FOV rectangle size
	var size_changed := false
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
	var top := fov_frame.get_node("Top")
	var bottom := fov_frame.get_node("Bottom")
	var left := fov_frame.get_node("Left")
	var right := fov_frame.get_node("Right")

	# Horizontal bars (top and bottom)
	var h_width := rect_half_width * 2
	top.position = Vector3(0, rect_half_height, -rect_distance)
	bottom.position = Vector3(0, -rect_half_height, -rect_distance)
	_set_capsule_length(top, h_width)
	_set_capsule_length(bottom, h_width)
	top.rotation_degrees = Vector3(0, 0, 90)
	bottom.rotation_degrees = Vector3(0, 0, 90)

	# Vertical bars (left and right)
	var v_height := rect_half_height * 2
	left.position = Vector3(-rect_half_width, 0, -rect_distance)
	right.position = Vector3(rect_half_width, 0, -rect_distance)
	_set_capsule_length(left, v_height)
	_set_capsule_length(right, v_height)

func _set_capsule_length(node: MeshInstance3D, length: float) -> void:
	"""Set the capsule mesh height (length along its axis)."""
	var mesh: CapsuleMesh = node.mesh
	mesh.height = length

func _update_stats() -> void:
	"""Calculate and display FOV based on rectangle size and distance."""
	# FOV = 2 * atan(half_size / distance)
	var h_fov_rad := 2.0 * atan(rect_half_width / rect_distance)
	var v_fov_rad := 2.0 * atan(rect_half_height / rect_distance)

	var h_fov_deg := rad_to_deg(h_fov_rad)
	var v_fov_deg := rad_to_deg(v_fov_rad)

	stats_label.text = "FOV Tester\nH: %.1f°\nV: %.1f°" % [h_fov_deg, v_fov_deg]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reload"):
		print("Reloading...")
		get_tree().reload_current_scene()
