import fs from 'node:fs/promises';
import path from 'node:path';
import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

// 以对象/字段定位已有行：只更新说明与基线，保留策划当前值、页签和原有计算。
const root=process.argv[2]||process.cwd();
const file=process.argv[3]||path.join(root,'outputs/planning/策划参数.xlsx');
const onlyTarget=process.argv.find(a=>a.startsWith('--target='))?.slice(9);
const catalog=JSON.parse(await fs.readFile(path.join(root,'content/rules/planning_parameters.json'),'utf8')).filter(r=>!onlyTarget||r.target===onlyTarget);
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(file));
// 仅显式点名的字段采用新默认作为当前值，其余人工调整继续保留。
const adoptDefaults=new Set(process.argv.filter(a=>a.startsWith('--adopt-default=')).map(a=>a.slice('--adopt-default='.length)));
if(process.argv.includes('--preview')){
  const image=await wb.render({sheetName:'07 分界线表现',range:'A1:G22',scale:1,format:'png'});
  await fs.writeFile(path.join(root,'builds/planning/07-before.png'),new Uint8Array(await image.arrayBuffer()));
  console.log((await wb.inspect({kind:'table',range:"'07 分界线表现'!A12:J22",include:'values,formulas',tableMaxRows:11,tableMaxCols:10})).ndjson);
  process.exit(0);
}
const locations=new Map(), previous=new Map(), refs={}, occupied=new Map();
const groups=[...new Set(catalog.map(r=>r.section))];
const names=new Set((await wb.inspect({kind:'sheet',include:'id,name'})).ndjson.split('\n').filter(Boolean).map(line=>JSON.parse(line).name));
const retiredNames={'boundary/period_sec':'缓流周期','boundary/stream_amplitude_px':'水带起伏','boundary/curl_amplitude_px':'大浪回卷','boundary/beat_enabled':'节拍回应','boundary/beat_amplitude_px':'节拍舒张幅度'};
Object.assign(retiredNames,{'boundary/wave_height_px':'大浪高度','boundary/advance_px':'浪身推进','boundary/curl_travel_px':'翻卷行程','boundary/foam_strength':'拍落白沫强度'});
Object.assign(retiredNames,{'boundary/bar_interval':'卷流接替间隔','boundary/vortex_outer_radius_px':'漩涡外半径','boundary/vortex_sweep_degrees':'卷入角度'});
for(const name of groups){
  if(!names.has(name)){
    const sheet=wb.worksheets.add(name);
    sheet.showGridLines=false;
    sheet.getRange('A2').values=[[name.slice(3)]];
    sheet.getRange('A3').values=[['修改黄色“当前值”，保存后重新装载关卡。比例用小数，开关用 0 / 1。']];
    sheet.getRange('A5:J5').values=[['参数','当前值','原型默认','单位','建议试调区间','每次建议改动','作用与注意事项','配置对象','字段名','来源（Game 内）']];
    sheet.getRange('A2:J5').format.font={name:'Microsoft YaHei',size:11,color:'#27363A'};
    sheet.getRange('A2').format.font={size:16,bold:true};
    sheet.getRange('A5:J5').format={fill:'#3F5967',font:{bold:true,color:'#FFFFFF'},rowHeight:30};
    for(const [col,width] of Object.entries({A:34,B:13,C:13,D:15,E:30,F:18,G:72,H:32,I:40,J:58})) sheet.getRange(`${col}1:${col}12`).format.columnWidth=width;
    sheet.freezePanes.freezeRows(5); sheet.freezePanes.freezeColumns(1);
  }
  const sheet=wb.worksheets.getItem(name);
  const values=sheet.getRange('A6:J300').values;
  values.forEach((v,i)=>{
    if(v.some(value=>value!==null&&value!=='')) occupied.set(name,i+6);
    if(String(v[0]||'').startsWith('已停用：')){
      const old=String(v[0]).slice(4);sheet.getRange(`A${i+6}`).values=[['已停用：'+(retiredNames[old]||old)]];
      sheet.getRange(`B${i+6}`).format.fill='#E7E8EA';
    }
    if(v[7]==='rules'||v[7]==='boundary'||v[7]==='actors'||v[7]==='boss'||v[7]==='ui_flame'||v[7]==='ui_guides'||v[7]==='judgment'||String(v[7]||'').startsWith('pet:')||String(v[7]||'').startsWith('reward:')){
      const key=v[7]+'/'+v[8]; locations.set(key,{sheet,row:i+6}); previous.set(key,v[1]);
    }
  });
}
// 旧共用伤害只迁移到 Tap 和空按；Hold/Ghost 是新机制，采用各自新默认。
if(locations.has('rules/miss_damage')&&!locations.has('rules/tap_miss_damage')){
  locations.set('rules/tap_miss_damage',locations.get('rules/miss_damage'));
  previous.set('rules/tap_miss_damage',previous.get('rules/miss_damage'));
  previous.set('rules/stray_input_damage',previous.get('rules/miss_damage'));
  locations.delete('rules/miss_damage');
}
for(const entry of catalog){
  const key=entry.target+'/'+entry.key;
  let location=locations.get(key);
  if(!location){
    const sheet=wb.worksheets.getItem(entry.section);
    const last=Math.max(5,occupied.get(entry.section)||5,...[...locations.values()].filter(v=>v.sheet.name===entry.section).map(v=>v.row));
    location={sheet,row:last+1}; locations.set(key,location);
    occupied.set(entry.section,last+1);
    const range=sheet.getRange(`A${last+1}:J${last+1}`);
    range.format={font:{name:'Microsoft YaHei',size:11,color:'#27363A'},rowHeight:46,verticalAlignment:'center'};
    sheet.getRange(`B${last+1}`).format.fill='#FFF0C2';
    sheet.getRange(`G${last+1}`).format.wrapText=true;
    if(entry.type!=='string') sheet.dataValidations.add({range:`B${last+1}`,rule:{type:entry.type==='float'?'decimal':'whole',operator:'between',formula1:entry.minimum,formula2:entry.maximum}});
  }
  const {sheet,row}=location;
  const baseline=entry.type==='string'?entry.default:Number(entry.default);
  // 分界线重编排会扩大厚度范围，已有输入格也需要同步其允许范围。
  if(entry.target==='boundary'||key==='rules/hold_segment_damage') sheet.getRange(`B${row}`).dataValidation={rule:{type:entry.type==='float'?'decimal':'whole',operator:'between',formula1:entry.minimum,formula2:entry.maximum}};
  sheet.getRange(`A${row}:J${row}`).values=[[entry.name,previous.has(key)&&!adoptDefaults.has(key)?previous.get(key):baseline,baseline,entry.unit,entry.suggested,entry.step,entry.meaning,entry.target,entry.key,entry.source]];
  sheet.getRange(`B${row}:C${row}`).setNumberFormat(entry.type==='string'?'@':entry.unit==='比例'?'0.0%':entry.type==='float'?'0.0000':'0');
  sheet.getRange(`F${row}`).setNumberFormat(entry.unit==='比例'?'0.0%':Number.isInteger(entry.step)?'0':'0.0000');
  refs[key]=`'${sheet.name}'!B${row}`;
}
// 退役行保留人工数值供查看，移除机器键，不再参与运行时配置。
for(const [key,{sheet,row}] of locations){
  if(!catalog.some(e=>e.target+'/'+e.key===key)){
    sheet.getRange(`A${row}`).values=[['已停用：'+(retiredNames[key]||key)]];
    sheet.getRange(`B${row}`).format.fill='#E7E8EA';
    sheet.getRange(`H${row}:I${row}`).values=[['','']];
  }
}
if(!onlyTarget){
const intro=wb.worksheets.getItem('使用与量级');
// 连续性标识是文本，留足宽度，不能套用数值列的窄格式。
const actors=wb.worksheets.getItem('08 角色移动');
actors.getRange('B1:C12').format.columnWidth=22;
actors.getRange('A3').values=[['修改黄色当前值；参考层填写连续性标识，留空使用静息。']];
intro.getRange('B4').values=[['在各参数页修改黄色 B 列，Ctrl+S 保存。']];
const ref=k=>refs['rules/'+k];
intro.getRange('A16').values=[['无随从：耗尽魂火所需 Tap 漏击组']];
intro.getRange('B16').formulas=[[`=IF(${ref('tap_miss_damage')}=0,"不扣血",ROUNDUP(${ref('max_soul_fire')}/${ref('tap_miss_damage')},0))`]];
intro.getRange('A20').values=[['鬼金羊基础：每组 Tap 伤害（点）']];
intro.getRange('B20').formulas=[[`=ROUND(${ref('tap_miss_damage')}*(1-${refs['pet:gui_jin_yang:base/damage_reduction']}),0)`]];
intro.getRange('A27:A29').values=[['无随从：每拍 Hold 漏失身体伤害'],['无随从：漏掉两拍 Hold 的伤害'],['无随从：耗尽魂火所需 Ghost 漏击数']];
intro.getRange('B27:B29').formulas=[
  [`=${ref('hold_segment_damage')}/${ref('hold_damage_segment_beats')}`],
  [`=ROUND(2*B27,0)`],
  [`=IF(${ref('ghost_miss_damage')}=0,"不扣血",ROUNDUP(${ref('max_soul_fire')}/${ref('ghost_miss_damage')},0))`]
];
intro.getRange('A27:B29').format={font:{name:'Microsoft YaHei',size:11,color:'#27363A'},rowHeight:30};
intro.getRange('A31').values=[['参数增删或含义变化时同步目录和本表；同步工具按字段保留黄色当前值。']];
intro.getRange('A31').format.font={name:'Microsoft YaHei',size:11,color:'#27363A'};
}
if(groups.includes('11 关卡奖励')) {
  const rewards=wb.worksheets.getItem('11 关卡奖励');
  rewards.getRange('A3').values=[['修改黄色当前值，下次正式装载生效。玄同收服、至臻进阶；不会撤回既有奖励。']];
  rewards.getRange('B1:C30').format.columnWidth=20;
}
if(onlyTarget==='boss')wb.worksheets.getItem('09 BOSS 表现').getRange('A3').values=[['修改黄色当前值，重新装载关卡或 BOSS 审看场景后生效；对象和绑定可覆盖战斗及发射默认值。']];
if(onlyTarget==='ui_guides')wb.worksheets.getItem('12 开屏引导').getRange('A3').values=[['修改黄色当前值，下次启动正式游戏生效；操作说明由玩家确认后继续。']];
if(onlyTarget==='ui_flame')wb.worksheets.getItem('10 UI 火框').getRange('A3').values=[['修改黄色当前值，重新打开 UI 火框审看场景后生效；本轮尚未替换正式界面。']];
wb.recalculate();
for(const entry of catalog){
  const key=entry.target+'/'+entry.key;
  if(previous.has(key)&&!adoptDefaults.has(key)){
    const {sheet,row}=locations.get(key);
    if(sheet.getRange(`B${row}`).values[0][0]!==previous.get(key)) throw Error('当前值被覆盖：'+key);
  }
}
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!',options:{useRegex:true,maxResults:10}})).ndjson);
for(const name of onlyTarget?groups:['02 魂火与惩罚','03 调频','07 分界线表现','08 角色移动','11 关卡奖励','使用与量级']){
  const preview=await wb.render({sheetName:name,range:name==='使用与量级'?'A1:B32':name==='03 调频'?'A5:G19':name==='07 分界线表现'?'A1:G28':'A1:G14',scale:1,format:'png'});
  await fs.writeFile(path.join(root,`builds/planning/${name}-updated.png`),new Uint8Array(await preview.arrayBuffer()));
}
await (await SpreadsheetFile.exportXlsx(wb)).save(file);
console.log(`同步 ${catalog.length} 个字段，采用新默认：${[...adoptDefaults].join(',')||'无'}；其他当前值已保留：${file}`);
