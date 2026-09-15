import fs from 'node:fs/promises';
import path from 'node:path';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';

// 在带 bundled node_modules junction 的工作目录运行，不向游戏安装 Node 依赖。
const root = process.argv[2] || process.cwd();
if (await fs.stat(path.join(root,'outputs/planning/策划参数.xlsx')).then(()=>true,()=>false)) {
  await import('./sync_workbook.mjs');
  process.exit(0);
}
const rows = JSON.parse(await fs.readFile(path.join(root,'content/rules/planning_parameters.json'),'utf8'));
const wb = Workbook.create();
const intro = wb.worksheets.add('使用与量级');
const sheets = new Map([...new Set(rows.map(r=>r.section))].map(name=>[name,wb.worksheets.add(name)]));
const refs = {};
for (const [name,sheet] of sheets) {
  const entries = rows.filter(r=>r.section===name);
  sheet.showGridLines=false;
  sheet.getRange('A2').values=[[name.slice(3)]];
  sheet.getRange('A3').values=[['修改黄色“当前值”，保存后重新装载关卡。比例用小数，开关用 0 / 1。']];
  sheet.getRange('A5:J5').values=[['参数','当前值','原型默认','单位','建议试调区间','每次建议改动','作用与注意事项','配置对象','字段名','来源（Game 内）']];
  sheet.getRange(`A6:J${entries.length+5}`).values=entries.map(r=>[
    r.name,Number(r.default),Number(r.default),r.unit,r.suggested,r.step,r.meaning,r.target,r.key,r.source]);
  sheet.getRange(`A2:J${entries.length+5}`).format.font={name:'Microsoft YaHei',size:11,color:'#27363A'};
  sheet.getRange('A2').format.font={size:16,bold:true};
	 sheet.getRange('A2:J2').format.rowHeight=26;
  sheet.getRange('A5:J5').format={fill:'#3F5967',font:{bold:true,color:'#FFFFFF'},rowHeight:30};
  sheet.getRange(`A6:J${entries.length+5}`).format.rowHeight=36;
  sheet.getRange(`A5:J${entries.length+5}`).format.verticalAlignment='center';
  sheet.getRange(`B6:B${entries.length+5}`).format.fill='#FFF0C2';
  sheet.getRange(`G6:G${entries.length+5}`).format.wrapText=true;
  for (const [col,width] of Object.entries({A:34,B:13,C:13,D:15,E:30,F:18,G:72,H:32,I:40,J:58})) sheet.getRange(`${col}1:${col}${entries.length+5}`).format.columnWidth=width;
  sheet.freezePanes.freezeRows(5);
  sheet.freezePanes.freezeColumns(1);
  entries.forEach((r,i)=>{
    const row=i+6;
    refs[r.target+'/'+r.key]=`'${name}'!B${row}`;
    sheet.getRange(`B${row}:C${row}`).setNumberFormat(r.unit==='比例'?'0.0%':r.type==='float'?'0.00':'0');
    sheet.getRange(`F${row}`).setNumberFormat(r.unit==='比例'?'0.0%':Number.isInteger(r.step)?'0':'0.00');
    sheet.dataValidations.add({range:`B${row}`,rule:{type:r.type==='float'?'decimal':'whole',operator:'between',formula1:r.minimum,formula2:r.maximum}});
  });
}
intro.showGridLines=false;
intro.getRange('A2').values=[['冥河，冥河！  策划调参']];
intro.getRange('A4:B12').values=[
 ['使用方式','在六个参数页修改黄色 B 列，Ctrl+S 保存。'],
 ['生效时间','工程内重新进入关卡；写谱器重新打开谱面，或修改谱面以重建预览。'],
 ['本局参数','暂停恢复、定位和普通局内重试保留原参数；重新装载才读取新表。'],
 ['默认值','C 列是 2026-09-14 原型基线；恢复时复制 C 列，粘贴为 B 列数值。'],
 ['比例与开关','例如 10% 可直接输入 10% 或 0.1；关闭=0，开启=1。'],
 ['调整建议','区间是本项目首轮试调建议，不是行业标准或强制范围。'],
 ['伤害与测试','工程 s01～s08 都是不死测试关；正式 JSON 谱面默认可失败。'],
 ['随从','仅装备时生效；默认写谱器预览无随从。改数值不会自动改技能原文。'],
 ['发布程序','旧 build 尚不支持本表。下一次构建后，可放 EXE 旁 planning/策划参数.xlsx。'],
 ];
intro.getRange('A15:B15').values=[['随当前值计算','结果']];
intro.getRange('A16:A21').values=[['无随从：耗尽魂火所需伤害组'],['Perfect 完整窗口（ms）'],['Good / Perfect 基础分比例'],['最高 Combo 倍率开始的连击数'],['鬼金羊基础：每次受伤（点）'],['调频一程 1 s：满幅理想耗时（s）']];
const r=k=>refs['rules/'+k];
intro.getRange('B16:B21').formulas=[
 [`=IF(${r('tap_miss_damage')}=0,"不扣血",ROUNDUP(${r('max_soul_fire')}/${r('tap_miss_damage')},0))`],
 [`=${r('perfect_window_ms')}*2`],
 [`=IF(${r('perfect_score')}=0,"无基准",${r('good_score')}/${r('perfect_score')})`],
 [`=${r('combo_steps_to_max')}+1`],
 [`=ROUND(${r('tap_miss_damage')}*(1-${refs['pet:gui_jin_yang:base/damage_reduction']}),0)`],
 [`=MAX(1-${r('tuning_speed_tolerance_ms')}/1000,0.001)`],
 ];
intro.getRange('A23').values=[['改变频率范围、每 Hz 尺度后，原有 Tuning 角度可能超出可编排范围，需要复查谱面。']];
intro.getRange('A25').values=[['详细语义、停用字段及逐关配置入口见 docs/planning/README.md。']];
intro.getRange('A2:F25').format.font={name:'Microsoft YaHei',size:11,color:'#27363A'};
intro.getRange('A2').format.font={size:16,bold:true};
intro.getRange('A2:B2').format.rowHeight=26;
intro.getRange('A4:A21').format.columnWidth=43;
intro.getRange('B4:B21').format.columnWidth=98;
intro.getRange('A4:B12').format.rowHeight=30;
intro.getRange('A15:B15').format={fill:'#3F5967',font:{bold:true,color:'#FFFFFF'}};
intro.getRange('A16:B21').format.rowHeight=30;
intro.getRange('B18').setNumberFormat('0%');
intro.getRange('B21').setNumberFormat('0.000');
wb.recalculate();
console.log((await wb.inspect({kind:'table',range:'使用与量级!A16:B21',include:'values,formulas',tableMaxRows:6,tableMaxCols:2})).ndjson);
// 验证输入实际驱动计算，然后还原，不把试验数值交付给策划。
const health=sheets.get('02 魂火与惩罚');
health.getRange('B7').values=[[10]];
wb.recalculate();
if (intro.getRange('B16').values[0][0]!==10) throw Error('伤害联动计算不正确');
health.getRange('B7').values=[[20]];
wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!',options:{useRegex:true,maxResults:10}})).ndjson);
await fs.mkdir(path.join(root,'outputs/planning'),{recursive:true});
for(const sheet of [intro,...sheets.values()]) {
  const preview=await wb.render({sheetName:sheet.name,range:sheet===intro?'A1:B26':`A1:G${rows.filter(r=>r.section===sheet.name).length+6}`,scale:1,format:'png'});
  await fs.writeFile(path.join(root,`builds/planning/${sheet.name}.png`),new Uint8Array(await preview.arrayBuffer()));
}
await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(root,'outputs/planning/策划参数.xlsx'));
await import('./sync_workbook.mjs');
