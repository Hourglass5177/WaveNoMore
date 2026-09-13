extends SceneTree
## 九项缺陷和动画资源交付回归；实际事件／GPU检查由 companion UI 测试完成。
var failures:=0
var output:=ProjectSettings.globalize_path("res://").path_join("../Levels/output/editor-fixes/roundtrip").simplify_path()
func _initialize() -> void:run.call_deferred()
func check(value: bool,label: String) -> void:
	if not value:failures+=1;printerr("FAIL ",label)
func settle(count:=4) -> void:
	for index in count:await process_frame
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var dialog=load("res://scenes/tools/level_studio/animation_import.tscn").instantiate();dialog.directory=output;root.add_child(dialog);await settle()
	var paths:=PackedStringArray()
	for index in [10,2,1]:
		var image:=Image.create(16,16,false,Image.FORMAT_RGBA8);image.fill(Color(float(index)/10.0,0,0,1))
		var path:=output.path_join("frame_%d.png"%index);image.save_png(path);paths.append(path)
	await dialog.load_images(paths)
	check(dialog.frames.get_frame_count("default")==3 and dialog._names[0]=="frame_1.png","连续图片自然排序")
	dialog._move_frame(0,2);check(dialog._names[2]=="frame_1.png","帧列表重排")
	var saved: Dictionary=await LevelAnimationAsset.write(dialog.frames,output,"连续帧")
	check(saved.error.is_empty(),"图片动画写入")
	var library:=LevelAssetLibrary.new();library.configure(output,[])
	var frames:=library.resolve(saved.path) as SpriteFrames
	check(frames!=null and frames.get_frame_count("default")==3,"工程内相对动画解析")
	dialog.source_sheet=frames.get_frame_texture("default",0);dialog.columns=2;dialog.rows=2;dialog.first_frame=1;dialog.last_frame=4;dialog.slice_sheet()
	check(dialog.frames.get_frame_count("default")==4 and dialog.frames.get_frame_texture("default",3).region==Rect2(8,8,8,8),"精灵表区域切割")
	var sheet: Dictionary=await LevelAnimationAsset.write(dialog.frames,output,"精灵表")
	frames=library.resolve(sheet.path)
	check(frames.get_frame_texture("default",3) is AtlasTexture and LevelAnimationAsset.dependencies(output.path_join(sheet.path)).size()==1,"精灵表只携带一个图集")
	await dialog.load_resource("res://assets/image/animation/monkey/monkey.tres")
	check(dialog.frames.get_frame_count("default")==16,"已有 SpriteFrames 导入")
	var resource: Dictionary=await LevelAnimationAsset.write(dialog.frames,output,"已有动作")
	dialog.queue_free();await settle()
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;workspace.recovery_path=output.path_join("recovery.json");root.add_child(workspace);await settle()
	workspace.document.directory=output;workspace._show_signature="";workspace._update_show()
	var cursor: int=workspace.document.cursor
	workspace.add_asset_object(resource.path);await settle()
	var id: String=workspace.selection[0]
	check(workspace.document.find("objects",id).type=="animated_sprite" and workspace.document.entries("tracks").size()==1,"拖入创建对象与动作轨")
	check(workspace.document.cursor==cursor+1,"对象与动作一次撤销")
	workspace.seek(450000);await settle()
	check(workspace.show_player().objects[id].get_node("Content").frame==5,"动作随歌曲时间定位")
	workspace.clear_object_asset_reference();await settle()
	check(workspace.show_player().objects[id].get_node_or_null("Content")==null,"清引用不创建空驱动")
	workspace.document.undo();await settle()
	check(workspace.document.find("objects",id).asset==resource.path,"清引用撤销恢复素材")
	workspace.auto_key=false;workspace.set_property("position",[1100.0,500.0]);await settle()
	check(workspace.document.find("objects",id).fields.position==[1100.0,500.0],"无动画修改基础变换")
	workspace.document.set_key(id,"position","song",1000000,[1200.0,500.0]);workspace.document.set_key(id,"position","outro",0,[55.0,66.0]);await settle()
	workspace.seek(1500000);await settle();workspace.set_property("position",[1250.0,520.0]);await settle()
	var position_track: Dictionary=workspace.document.entries("tracks").filter(func(track):return track.property=="position" and track.section=="song")[0]
	check(position_track.keys[0].time_us==0 and position_track.keys[0].value==[1150.0,520.0],"整段变换补区段起点")
	check(position_track.keys[1].value==[1250.0,520.0] and workspace.document.find("objects",id).fields.position==[1100.0,500.0],"整段动画调整不改全局基础")
	var outro: Dictionary=workspace.document.entries("tracks").filter(func(track):return track.section=="outro")[0]
	check(outro.keys[0].value==[55.0,66.0],"其他区段不受影响")
	workspace.auto_key=true;workspace.difficulty_only=true;workspace.set_property("position",[1280.0,540.0]);await settle()
	check(workspace.document.entries("tracks").filter(func(track):return track.property=="position" and track.section=="song").size()==1,"新轨范围不偷偷另建覆盖轨")
	check(workspace.document.find("tracks",position_track.id).keys.back().time_us==1500000,"自动关键帧创建当前时刻")
	workspace.select_objects(PackedStringArray([id]),position_track.id);workspace.delete_objects();await settle()
	check(workspace.document.find("objects",id).is_empty(),"轨道上下文明确删除对象")
	workspace.document.undo();await settle()
	check(workspace.selection==PackedStringArray([id]) and workspace.selected_track==position_track.id,"删除撤销恢复对象与轨道选区")
	var level: Dictionary=workspace.document.data.duplicate(true)
	check(LevelProjectIO.import_song("res://examples/level-studio/渡口演出/song/song.json",output).is_empty(),"复制测试歌曲")
	check(LevelProjectIO.save(level,output).is_empty(),"保存动画关卡")
	var windows_root:=output.replace("/","\\")
	check(LevelProjectIO.dependencies(level,windows_root)==LevelProjectIO.dependencies(level,output),"Windows 混合分隔符依赖保持相对路径")
	workspace.document.directory=windows_root
	check(workspace._save_as_to(output.path_join("windows-save-as").replace("/","\\")),"Windows 路径另存为")
	var saved_library:=LevelAssetLibrary.new();saved_library.configure(workspace.document.directory,[])
	check(saved_library.resolve(resource.path) is SpriteFrames,"另存为后实际图片齐全")
	workspace.document.directory=output
	var package:=output.path_join("animation.level.zip")
	check(LevelProjectIO.export_zip(level,output,package).is_empty(),"动画及依赖导出 ZIP")
	var reader:=ZIPReader.new();reader.open(package)
	check(reader.get_files().has(resource.path) and reader.get_files().has(resource.path.get_base_dir().path_join("image_0000.png")),"包内包含动画与实际贴图")
	reader.close()
	var isolated:=output.path_join("isolated")
	check(LevelProjectIO.unpack(package,isolated).is_empty(),"解压到独立目录")
	# 暂时移开原素材目录，验证加载并不借助原目录或导入缓存。
	var origin_assets:=output.path_join("assets");var away:=output.path_join("source-away")
	check(DirAccess.rename_absolute(origin_assets,away)==OK,"隔离原素材")
	var isolated_library:=LevelAssetLibrary.new();isolated_library.configure(isolated,[])
	var portable:=isolated_library.resolve(resource.path) as SpriteFrames
	check(portable!=null and portable.get_frame_count("default")==16,"无原目录仍能加载动画")
	check(DirAccess.rename_absolute(away,origin_assets)==OK,"还原测试来源")
	await test_external_resource()
	test_transform_ranges()

	workspace.queue_free();await settle()
	print("EDITOR FIXES failures=",failures);quit(1 if failures else 0)

func test_external_resource() -> void:
	var external:=output.path_join("external-source")
	DirAccess.make_dir_recursive_absolute(external.path_join("assets"))
	var project:=FileAccess.open(external.path_join("project.godot"),FileAccess.WRITE);project.store_string("config_version=5\n");project.close()
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color.MAGENTA);image.save_png(external.path_join("assets/shared.png"))
	var source:=FileAccess.open(external.path_join("test.tres"),FileAccess.WRITE)
	source.store_string('[gd_resource type="SpriteFrames" format=3]\n[ext_resource type="Texture2D" path="res://assets/shared.png" id="1"]\n[resource]\nanimations = [{"frames": [{"duration": 2.0, "texture": ExtResource("1")}], "loop": false, "name": &"wave", "speed": 9.0}]\n');source.close()
	image.fill(Color.GREEN)
	var borrowed:=ImageTexture.create_from_image(image);borrowed.take_over_path("res://assets/shared.png")
	var result:=LevelAnimationAsset.import_resource(external.path_join("test.tres"))
	check(result.error.is_empty() and result.frames.get_animation_speed("wave")==9 and result.frames.get_frame_duration("wave",0)==2,"外部 SpriteFrames 保留动作与帧时长")
	check(result.frames.get_frame_texture("wave",0).get_image().get_pixel(0,0)==Color.MAGENTA,"读取外部图片而非当前同名图片")
	check(ResourceLoader.load("res://assets/shared.png")==borrowed,"来源导入还原原工程缓存")
	ResourceSaver.save(result.frames,external.path_join("test.res"))
	var binary:=LevelAnimationAsset.import_resource(external.path_join("test.res"))
	check(binary.error.is_empty() and binary.frames.has_animation("wave"),"二进制 SpriteFrames 导入")
	DirAccess.rename_absolute(external.path_join("assets/shared.png"),external.path_join("replacement.png"))
	var missing:=LevelAnimationAsset.import_resource(external.path_join("test.tres"))
	check(not missing.error.is_empty() and missing.missing.size()==1,"缺失图片不借同名缓存")
	var relocated:=LevelAnimationAsset.import_resource(external.path_join("test.tres"),{"res://assets/shared.png":external.path_join("replacement.png")})
	check(relocated.error.is_empty(),"逐项重新定位图片")
	borrowed.resource_path=""

func test_transform_ranges() -> void:
	var doc:=LevelDocument.new();var object_data:=LevelFormat.object("sprite");var level:=LevelFormat.new_level();level.show.objects=[object_data]
	for scope in [[],["hard"]]:
		var track:=LevelFormat.track(object_data.id,"scale");track.difficulties=scope;track.keys=[LevelFormat.key(0,[2.0,3.0]),LevelFormat.key(1000000,[4.0,6.0])];track.keys[0].interpolation="bezier";level.show.tracks.append(track)
	doc.reset(level)
	var before:=object_data.duplicate(true);before.fields=LevelShowSampler.object_state(doc.data.show,before,"song",1000000,"hard")
	var after:=before.duplicate(true);after.fields.scale=[8.0,3.0]
	var result:=LevelTransformEdit.build(doc,[before],[after],"song",1000000,"hard",false,true)
	check(result.error.is_empty() and result.show.tracks[0].keys[0].value==[4.0,1.5] and result.show.tracks[1].keys[1].value==[8.0,3.0],"共同与难度轨同时按比例整体调整")
	check(result.show.tracks[0].keys[0].interpolation=="bezier" and result.show.tracks[0].difficulties.is_empty(),"整体调整保留曲线与范围")
	var key_id: String=doc.entries("tracks")[1].keys[1].id
	result=LevelTransformEdit.build(doc,[before],[after],"song",1000000,"hard",false,true,PackedStringArray([key_id]))
	check(result.show.tracks[0]==doc.entries("tracks")[0] and result.show.tracks[1].keys[0]==doc.entries("tracks")[1].keys[0],"明确选键不改变其他轨道与键")
	doc.entries("tracks")[0].locked=true
	result=LevelTransformEdit.build(doc,[before],[after],"song",1000000,"hard",false,true)
	check(not result.error.is_empty(),"锁定参与轨时拒绝部分调整")
	var parent:=LevelFormat.object("group");parent.fields.position=[100.0,0.0];object_data.parent_id=parent.id
	level.show.objects=[parent,object_data];level.show.tracks=[];doc.reset(level)
	var moved_parent:=parent.duplicate(true);moved_parent.fields.position=[150.0,0.0]
	var moved_child:=object_data.duplicate(true);moved_child.fields.position=[2000.0,540.0]
	result=LevelTransformEdit.build(doc,[parent,object_data],[moved_parent,moved_child],"song",0,"hard",false,false)
	check(result.show.objects[1].fields.position==object_data.fields.position and result.show.objects[0].fields.position==[150.0,0.0],"父子多选只变换选区根对象")
