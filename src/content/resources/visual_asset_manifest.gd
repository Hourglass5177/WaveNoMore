## 美术资源清单根对象，供 ArtLab 和发布校验器按稳定 asset_id 查验正式交付物。
@tool
class_name VisualAssetManifest
extends Resource

## 清单格式版本；只随字段结构迁移递增。
@export var schema_version: int = 1
## 本清单稳定 ID，便于 ArtLab 和发布流程选择对应资产集。
@export var manifest_id: String = ""
## 所有资产交付条目；每项 asset_id 必须唯一。
@export var entries: Array[VisualAssetEntry] = []


func entry_by_id(asset_id: String) -> VisualAssetEntry:
	for entry: VisualAssetEntry in entries:
		if entry != null and entry.asset_id == asset_id:
			return entry
	return null
