import fs from 'node:fs/promises';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';
// 临时副本模拟策划已改数值，再真正导入、同步、重开；不改交付工作簿。
const root=process.argv[2]||process.cwd();
const file=path.join(root,'builds/planning/sync-preservation.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(root,'outputs/planning/策划参数.xlsx')));
const health=wb.worksheets.getItem('02 魂火与惩罚');
health.getRange('B7').values=[[17]];
health.getRange('B11').values=[[0.125]];
await (await SpreadsheetFile.exportXlsx(wb)).save(file);
const result=spawnSync(process.execPath,[path.join(root,'builds/planning/sync_workbook.mjs'),root,file],{encoding:'utf8'});
if(result.status!==0) throw Error(result.stderr||result.stdout);
const reopened=await SpreadsheetFile.importXlsx(await FileBlob.load(file));
const edited=reopened.worksheets.getItem('02 魂火与惩罚');
if(edited.getRange('B7').values[0][0]!==17||edited.getRange('B11').values[0][0]!==0.125) throw Error('同步覆盖了策划当前值');
console.log('SYNC PRESERVATION: Tap 17、Hold 单位拍长 0.125 保存、同步、重开后保留');
