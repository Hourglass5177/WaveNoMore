extends SceneTree
var failures:=0
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr(label)
func _initialize() -> void:
	for mirrored in [false,true]:
		var spawn:=Vector2(1850,100) if not mirrored else Vector2(70,980)
		var cue:=Vector2(1200,400) if not mirrored else Vector2(720,680)
		var bell:=Vector2(900,450) if not mirrored else Vector2(1020,630)
		var profile:=NoteApproachPath.build_profile(spawn,cue,bell,160,120)
		for origin in [Vector2(960,200),Vector2(100,400),Vector2(1800,700)]:
			var path:=BossEmissionPath.scatter(origin,profile,2.25,0.2,"level:boss:note",600,30)
			var first:=BossEmissionPath.sample(path,0)
			var last:=BossEmissionPath.sample(path,path.duration_us)
			check(first.position.distance_to(origin)<0.01,"出手位置一致")
			check(last.position.distance_to(spawn)>10,"不得汇入固定出生点")
			var ratio:=1.0-float(path.join_lead_us)/2250000
			check(last.position.distance_to(NoteApproachPath.point_at_ratio(profile,ratio))<0.01,"接点位置连续")
			check(last.velocity.distance_to(NoteApproachPath.tangent_at_ratio(profile,ratio)*NoteApproachPath.length(profile)/2.25)<0.01,"接点速度连续")
			check(path.duration_us+path.join_lead_us>=3250000,"至少多一秒预读")
			var previous:=0.0
			for step in 101:
				var sample:=BossEmissionPath.sample(path,path.duration_us*step/100)
				check(sample.distance>=previous-0.001,"路程不能回退");previous=sample.distance
	print("BOSS PATH failures=",failures);quit(failures)
