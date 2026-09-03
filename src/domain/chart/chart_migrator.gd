class_name ChartMigrator
extends RefCounted

## 谱面版本入口。始终返回源资源的深拷贝，避免运行时意外改写磁盘数据。
## Schema 1 的共同游标曲线无法判断应属于哪口钟，因此必须由谱师手工改写。

static func migrate(source: SongChart, target_version: int = SongChart.CURRENT_SCHEMA_VERSION) -> Dictionary:
	var report := ValidationReport.new()
	if source == null:
		report.add_error(&"chart.null", "SongChart is null.")
		return {"ok": false, "chart": null, "report": report}
	if source.schema_version > target_version:
		report.add_error(
			&"schema.newer_than_runtime",
			"Chart schema %d is newer than supported schema %d." % [source.schema_version, target_version]
		)
		return {"ok": false, "chart": null, "report": report}
	if source.schema_version < SongChart.CURRENT_SCHEMA_VERSION:
		report.add_error(
			&"schema.v1_tuning_requires_reauthoring",
			"Schema %d cannot be migrated automatically: shared tune curves and fixed Su targets must be reauthored as independent bell sliders and dynamic manifestations." % source.schema_version
		)
		return {"ok": false, "chart": null, "report": report}
	if source.schema_version != target_version:
		report.add_error(
			&"schema.migration_missing",
			"No explicit migration path from schema %d to %d." % [source.schema_version, target_version]
		)
		return {"ok": false, "chart": null, "report": report}
	var migrated: SongChart = source.duplicate(true) as SongChart
	return {"ok": not report.has_errors(), "chart": migrated, "report": report}
