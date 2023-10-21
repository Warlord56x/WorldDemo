extends CharacterBody3D

class_name Player

const SM_PARAM: String = "parameters/StateMachine/"
const A_PARAM: String = "parameters/"

const ROTATION_INTERPOLATE_SPEED = 10
const MOTION_INTERPOLATE_SPEED = 10
const MIN_AIRBORNE_TIME = 0.1

enum A_ONESHOT {
	NONE,
	FIRE,
	ABORT,
	FADE_OUT,
}

enum ATTACKS {
	state_0,
	state_1,
	state_2,
}

var airborne_time = 100

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * ProjectSettings.get_setting("physics/3d/default_gravity_vector")

@export var speed = 0.2
@export var jump_velocity = 4.5

@onready var camera_base := $CameraBase
@onready var camera_rot := $CameraBase/CameraRot
@onready var camera_spring := $CameraBase/CameraRot/Arm

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = animation_tree[SM_PARAM + "playback"]
@onready var attack_timer: Timer = $AttackTimer

@onready var mesh := $thief
var no_rotate := false
var input := Vector2()
var motion := Vector2()
var orientation := Transform3D()

var attack_variations: int = 3
var current_attack_variation: int = 0


func rotate_camera(move : Vector2) -> void:
	camera_base.rotate_y(-move.x)
	# After relative transforms, camera needs to be renormalized.
	camera_base.orthonormalize()
	camera_rot.rotation.x = clamp(camera_rot.rotation.x - move.y, -deg_to_rad(75), deg_to_rad(0))


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
	if event.is_action_released("wheel_down"):
		var tween = get_tree().create_tween()
		tween.tween_property(camera_spring, "spring_length", clamp(value+1.0, 2.0, 10.0), 0.1)


func _ready() ->void:
	orientation = mesh.global_transform


func _physics_process(delta : float) -> void:
	motion = Input.get_vector("move_l", "move_r", "move_b", "move_f")

	if Input.is_action_pressed("l_click"):
		if !animation_tree[A_PARAM + "Attack/active"]:
			if attack_timer.is_stopped():
				current_attack_variation = 0
			animation_tree[A_PARAM + "AttackSwitch/transition_request"] = ATTACKS.keys()[current_attack_variation]
			animation_tree[A_PARAM + "Attack/request"] = A_ONESHOT.FIRE
			current_attack_variation = (current_attack_variation + 1) % attack_variations
			await animation_tree.animation_finished
			attack_timer.start()

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
		if airborne_time > 0.1:
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

	

	if motion:
		var target = camera_x * -motion.x + camera_z
		if target.length() > 0.001:
			var q_from = orientation.basis.get_rotation_quaternion()
			var q_to = Transform3D().looking_at(target, Vector3.UP).basis.get_rotation_quaternion()
			# Interpolate current rotation with desired one.
			orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))
		orientation.origin = Basis(camera_base.transform.basis) * Vector3(motion.x, 0, -motion.y).normalized()

	orientation.origin *= speed


	var h_velocity = orientation.origin / delta
	velocity.x = h_velocity.x
	velocity.z = h_velocity.z

	velocity += gravity * delta
	move_and_slide()

	var last_strafe_blend_pos = animation_tree[SM_PARAM + "StrafeRun/blend_position"]
	animation_tree[SM_PARAM + "StrafeRun/blend_position"] = Vector2(
		move_toward(last_strafe_blend_pos.x, sign(motion.x), 0.1),
		move_toward(last_strafe_blend_pos.y, sign(motion.y), 0.1)
	)

	orientation.origin = Vector3() # Clear accumulated root motion displacement (was applied to speed).
	orientation = orientation.orthonormalized() # Orthonormalize orientation.
	mesh.global_transform.basis = orientation.basis
