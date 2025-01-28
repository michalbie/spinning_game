extends KinematicBody2D

var Bullet = preload("res://Entities/Bullet/Bullet.tscn")
var HUD = preload("res://Scenes/HUD/HUD.tscn")

signal input_ready(input)
signal player_died

var Globals = preload("res://Scripts/Globals.gd")
export(preload("res://Scripts/Globals.gd").level) var move_speed
export(preload("res://Scripts/Globals.gd").level) var rotate_cooldown
export(preload("res://Scripts/Globals.gd").level) var rotate_speed
export(preload("res://Scripts/Globals.gd").level) var shoot_cooldown
export(preload("res://Scripts/Globals.gd").level) var bullet_speed
export(preload("res://Scripts/Globals.gd").level) var bullet_damage
export(preload("res://Scripts/Globals.gd").level) var bullet_range
export(preload("res://Scripts/Globals.gd").level) var hp
export (String) var description

var inside_circle = false
var switch_rotation = false
var rotate_direction = 1 #-1 - left, 1 - right
var shoot = false
var being_removed = false
var max_hp
var kills = 0

var observers_list = []
var hud
var is_server = false

func _ready():
	is_server = get_tree().is_network_server()
	connect("input_ready", Server, "_on_input_ready")
	move_speed = Globals.move_speed[move_speed]
	rotate_cooldown = Globals.rotate_cooldown[rotate_cooldown]
	rotate_speed = Globals.rotate_speed[rotate_speed]
	shoot_cooldown = Globals.shoot_cooldown[shoot_cooldown]
	bullet_speed = Globals.bullet_speed[bullet_speed]
	bullet_damage = Globals.bullet_damage[bullet_damage]
	bullet_range = Globals.bullet_range[bullet_range]
	hp = Globals.hp[hp]
	max_hp = hp
	
	if is_server == false and self.get_name() == str(get_tree().get_network_unique_id()):
		hud = HUD.instance()
		add_child(hud)
		GameManager.connect("game_started", hud, "initialize")
	elif is_server == true:
		hud = HUD.instance()
		add_child(hud)
		
	if self.get_name() == str(get_tree().get_network_unique_id()):
		self.get_node("Camera2D").current = true
		

func _physics_process(delta):
	if !is_server and str(get_tree().get_network_unique_id()) == self.get_name():
		if !being_removed:
			listen_inputs()
			send_inputs(delta)

func listen_inputs():
	if Input.is_action_just_pressed("switch_rotation"):
		switch_rotation = true
		
	if Input.is_action_pressed("shoot"):
		if $AnimationPlayer.is_playing() == false and $Body.frame != 1:
			$Blood.visible = false
			$Blood.rotation_degrees = 0
			if LobbyManager.players[get_tree().get_network_unique_id()]["class"] == "HeavyMachinegunner" or LobbyManager.players[get_tree().get_network_unique_id()]["class"] == "LightAssaulter":
				GameManager.world.get_node(self.get_name()).rpc("play_extended_recoil_animation")
			else:
				GameManager.world.get_node(self.get_name()).rpc("play_recoil_animation")

		shoot = true
		
	if Input.is_action_just_released("shoot"):
		$Blood.visible = false
		$Blood.rotation_degrees = 0
		if LobbyManager.players[get_tree().get_network_unique_id()]["class"] == "HeavyMachinegunner" or LobbyManager.players[get_tree().get_network_unique_id()]["class"] == "LightAssaulter":
			GameManager.world.get_node(self.get_name()).rpc("finish_extended_recoil_animation")

		shoot = false

func send_inputs(delta):
	var mouse_pos = get_global_mouse_position()
	var player_input = {}
	player_input['delta'] = delta
	player_input['mouse_pos'] = mouse_pos
	player_input['inside_circle'] = inside_circle
	player_input['switch_rotation'] = switch_rotation
	player_input['shoot'] = shoot
	switch_rotation = false
	shoot = false
	
	if !being_removed:
		emit_signal("input_ready", player_input)

func got_shot(dmg, source, bullet_rotation):
	if dmg >= hp:
		hp = 0
		being_removed = true
		GameManager.world.gameplay_info.rpc("update_kills_info", str(source), self.get_name())

		if source != "Fog" and source != "Heart attack":
			GameManager.world.get_node(str(source)).kills += 1
			GameManager.world.get_node(str(source)).hud.rpc_id(int(source), "update_kills", GameManager.world.get_node(str(source)).kills)
			for id in GameManager.world.get_node(str(source)).observers_list:
				GameManager.world.spectator_system.get_node("HUD").rpc_id(int(id), "update_kills", GameManager.world.get_node(str(source)).kills)
		else:
			SoundManager.rpc_id(int(self.get_name()), "stop_fog_sound")
			
		emit_signal("player_died")
		GameManager.world.rpc("kill_player", int(self.get_name()), source)
	else:
		hp -= dmg
		rpc("play_blood_animation", bullet_rotation)
		if hud != null:
			hud.rpc_id(int(self.get_name()), "update_hp", hp)
			for id in observers_list:
				GameManager.world.spectator_system.get_node("HUD").rpc_id(int(id), "update_hp", hp)
				
remotesync func append_observer(observer_id):
	observers_list.append(observer_id)
	
remotesync func erase_observer(observer_id):
	observers_list.erase(observer_id)
	
remote func play_blood_animation(bullet_rotation):
	$Blood.visible = false
	$Blood.rotation_degrees = 0
	$Blood.set_frame(0)
	$Blood.rotate(-self.rotation + bullet_rotation)
	$AnimationPlayer.play("BloodAnimation")
	
remotesync func play_recoil_animation():
	if(get_tree().get_network_unique_id() != 1):
		if LobbyManager.players[get_tree().get_network_unique_id()]["class"] == 'Soldier':
			$AnimationPlayer.play("SoldierRecoil")
		elif LobbyManager.players[get_tree().get_network_unique_id()]["class"] == "Sniper":
			$AnimationPlayer.play("SniperRecoil")
		elif LobbyManager.players[get_tree().get_network_unique_id()]["class"] == "CloseRifleman":
			$AnimationPlayer.play("CloseRiflemanRecoil")
	
	
remotesync func play_extended_recoil_animation():
	$AnimationPlayer.play("ExtendedRecoilStart")
	$Body.set_frame(1)
	
remotesync func finish_extended_recoil_animation():
	$AnimationPlayer.play("ExtendedRecoilEnd")
	

func _on_StandingCircle_mouse_entered():
	inside_circle = true

func _on_StandingCircle_mouse_exited():
	inside_circle = false

func _on_RotateCooldown_timeout():
	$RotateCooldown.stop()


func _on_ShootCooldown_timeout():
	$ShootCooldown.stop()


func _on_AnimationPlayer_animation_finished(anim_name):
	if anim_name == "BloodAnimation":
		$Blood.rotation_degrees = 0
		$Blood.set_frame(0)
		$Blood.visible = false


func _on_AnimationPlayer_animation_changed(old_name, new_name):
	if old_name == "BloodAnimation":
		$Blood.set_frame(0)
		$Blood.visible = false

		
