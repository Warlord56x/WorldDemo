extends CharacterBody3D

class_name Player

const SM_PARAM: String = "parameters/StateMachine/"

const ROTATION_INTERPOLATE_SPEED = 10
const MIN_AIRBORNE_TIME = 0.1

var airborne_time = 100

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * ProjectSettings.get_setting("physics/3d/default_gravity_vector")

@export var speed = 5.0
@export var jump_velocity = 4.5

@onready var camera_base := $CameraBase
@onready var camera_rot := $CameraBase/CameraRot
@onready var camera_spring := $CameraBase/CameraRot/Arm

@onready var animation_tree : AnimationTree = $AnimationTree
@onready var state_machine : AnimationNodeStateMachinePlayback = animation_tree[SM_PARAM + "playback"]

@onready var mesh := $Rogue_Hooded
var no_rotate := false
var orientation := Transform3D()
var root_motion := Transform3D()


func rotate_camera(move : Vector2) -> void:
	camera_base.rotate_y(-move.x)
	# After relative transforms, camera needs to be renormalized.
	camera_base.orthonormalize()
	camera_rot.rotation.x = clamp(camera_rot.rotation.x - move.y, -deg_to_rad(90), deg_to_rad(0))


func _input(event : InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			rotate_camera(event.relative * 0.001)
			no_rotate = false
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			rotate_camera(event.relative * 0.001)
			no_rotate = true

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) || Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var value = camera_spring.spring_length
	if event.is_action_released("wheel_up"):
		var tween = get_tree().create_tween()
		tween.tween_property(camera_spring, "spring_length", clamp(value-1.0, 2.0, 10.0), 0.1)
		tween.play()
	if event.is_action_released("wheel_down"):
		var tween = get_tree().create_tween()
		tween.tween_property(camera_spring, "spring_length", clamp(value+1.0, 2.0, 10.0), 0.1)
		tween.play()
	
#	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
#		var anim_time = state_machine.get_current_play_position()
#		if state_machine.get_current_node() == "combo1" and anim_time < 0.7 and anim_time > 0.4:
#			await test_timer.timeout
##			state_machine.travel("combo2")
#		else:
##			state_machine.travel("combo1")
#			test_timer.start()


func _ready() ->void:
	orientation = mesh.global_transform


func _physics_process(delta : float) -> void:

	var camera_basis : Basis = camera_rot.global_transform.basis
	var camera_z := camera_basis.z
	var camera_x := camera_basis.x

	camera_z.y = 0
	camera_z = camera_z.normalized()
	camera_x.y = 0
	camera_x = camera_x.normalized()

	# Jump/in-air logic.
	airborne_time += delta
	if is_on_floor():
		if airborne_time > 0.5:
			state_machine.travel("Jump_Land")
		airborne_time = 0

	var on_air = airborne_time > MIN_AIRBORNE_TIME

	if not on_air and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		on_air = true
		# Increase airborne time so next frame on_air is still true
		airborne_time = MIN_AIRBORNE_TIME

	if on_air:
		if (velocity.y > 0):
			state_machine.travel("Jump_Idle")

	var input_dir : Vector2 = Input.get_vector("move_l", "move_r", "move_b", "move_f")
	if not no_rotate:
		var target = camera_x * input_dir.x + camera_z
		if target.length() > 0.001:
			var q_from = orientation.basis.get_rotation_quaternion()
			var q_to = Transform3D().looking_at(target, Vector3.UP).basis.get_rotation_quaternion()
			# Interpolate current rotation with desired one.
			orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))

	var direction: Vector3 = (
		Basis(orientation.basis * -1 if no_rotate else camera_base.transform.basis) * Vector3(input_dir.x, 0, -input_dir.y)
	).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	velocity += gravity * delta
	move_and_slide()

	var last_blend_pos = animation_tree[SM_PARAM + "Run/blend_position"]
	animation_tree[SM_PARAM + "Run/blend_position"] = Vector2(
		move_toward(last_blend_pos.x, sign(-input_dir.x) if direction else 0.0, 0.1),
		move_toward(last_blend_pos.y, sign(input_dir.y) if direction else 0.0, 0.1)
	)

	orientation = orientation.orthonormalized() # Orthonormalize orientation.
	mesh.global_transform.basis = orientation.basis
