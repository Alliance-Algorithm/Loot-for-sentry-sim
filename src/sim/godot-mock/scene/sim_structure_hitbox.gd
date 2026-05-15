extends Area3D
## 比赛建筑受击区域。
## 仿照机器人装甲板方案，子弹命中后将伤害转发给所属结构目标。

@export var team := ""
@export var owner_target_path: NodePath
@export var hitbox_size := Vector3(1.5, 1.5, 1.5)

const ARMOR_LAYER := 1 << 5

var owner_target: Node = null


func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = ARMOR_LAYER
	collision_mask = 0

	if owner_target_path != NodePath():
		owner_target = get_node_or_null(owner_target_path)

	if owner_target == null:
		owner_target = get_parent()

	if get_child_count() == 0:
		_create_default_shape()


func on_bullet_hit(damage: int, from_team: String) -> bool:
	if from_team == team:
		return false

	if owner_target != null and owner_target.has_method("apply_structure_damage"):
		return bool(owner_target.call("apply_structure_damage", 100))
	return false


func _create_default_shape() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hitbox_size
	shape.shape = box
	add_child(shape)
