extends "res://src/app/app_main.gd"
## 白场集成测试跳过启动导航，保留正式路由与页面交接实现。
func _ready() -> void:
	theme = preload("res://content/ui/game_theme.tres")
	add_child(_jobs)
	AppRouter.route_requested.connect(_on_route_requested)
