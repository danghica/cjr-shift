import {test} from 'node:test';
import assert from 'node:assert/strict';
import {localTimestamp, localOrdinal, minuteDate, dateKey, duration, groupShifts} from './static/time.mjs';

test('civil minute bridge has the correct epoch and round trips current local time', () => {
  assert.equal(minuteDate(0).toISOString(), '0001-01-01T00:00:00.000Z');
  const now = new Date(2026, 10, 11, 9, 30);
  assert.equal(localTimestamp(now), '2026-11-11T09:30');
  assert.equal(minuteDate(localOrdinal(now)).toISOString(), '2026-11-11T09:30:00.000Z');
});
test('midnight splits group by their start day without timezone drift', () => {
  const midnight = localOrdinal(new Date(2026, 10, 12, 0, 0));
  const groups = [...groupShifts([[midnight-30,midnight],[midnight,midnight+60]])];
  assert.deepEqual(groups.map(([key])=>key), ['2026-11-12','2026-11-11']);
  assert.equal(dateKey(midnight-30), '2026-11-11');
});
test('newest first grouping preserves every independent piece', () => {
  assert.deepEqual([...groupShifts([[100,110],[200,210],[50,60]])][0][1], [[200,210],[100,110],[50,60]]);
});
test('duration totals use minutes, including long shifts and empty days', () => {
  assert.equal(duration(0),'0h 00m');
  assert.equal(duration(90),'1h 30m');
  assert.equal(duration(1500),'25h 00m');
  assert.equal(duration(-1),'0h 00m');
});

// Regression: a newly served form can talk to an older still-running backend.
test('missing missed-shift route explains server restart and preserves form guidance', async () => {
  const {responseFailure} = await import('./static/time.mjs');
  const error = responseFailure(404, 'missed-shift', {message:'Not found.'});
  assert.match(error.message, /does not support adding missed shifts/);
  assert.match(error.message, /Restart the UI server/);
  assert.match(error.message, /entered dates have been kept/);
  assert.equal(error.recovery, 'reload');
  assert.equal(responseFailure(404, 'missed-shift', {}).recovery, 'reload');
});
test('specific domain errors remain useful and unknown errors do not leak generic not-found text', async () => {
  const {responseFailure} = await import('./static/time.mjs');
  assert.equal(responseFailure(409, 'missed-shift', {message:'End must be later than start.'}).message, 'End must be later than start.');
  assert.match(responseFailure(503, 'missed-shift', {}).message, /Check your saved shifts/);
  assert.match(responseFailure(404, 'state', {}).message, /loading your shifts/);
});

test('background refresh preserves an unsupported-action error and does not resubmit the shift', async () => {
  const {readFile} = await import('node:fs/promises');
  const vm = await import('node:vm');
  const {responseFailure} = await import('./static/time.mjs');
  const nodes = new Map();
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, {textContent:'',hidden:true,disabled:false,lastChild:{textContent:''},setAttribute(){}});
    return nodes.get(id);
  };
  const state = {pending:null,shifts:[]};
  const responses = [
    {ok:true,status:200,body:{code:0,state}},
    {ok:false,status:404,body:{message:'Not found.'}},
    {ok:true,status:200,body:{code:0,state}},
    {ok:true,status:200,body:{code:0,state}}
  ];
  const calls = [];
  const context = vm.createContext({document:{getElementById:node,querySelectorAll:()=>[]},responseFailure,render(){},
    fetch:async (path,options) => {calls.push([path,options]); const next=responses.shift();return {...next,json:async()=>next.body};}});
  const source = await readFile(new URL('./static/app.js', import.meta.url),'utf8');
  const prefix = source.slice(source.indexOf('const $'),source.indexOf('function tick()'));
  context.browserRequest=async (path,data)=>context.fetch(`/api/${path}`,data===undefined?{cache:'no-store'}:{method:'POST',body:JSON.stringify(data)});
  vm.runInContext(prefix+'\nglobalThis.api = {refresh,change};',context);
  await context.api.refresh();
  await context.api.change('missed-shift',{start:'2026-11-11T09:00',end:'2026-11-11T10:00'});
  const message = node('error-message').textContent;
  assert.match(message,/Restart the UI server/);
  assert.equal(node('retry').textContent,'reload page');
  await context.api.refresh();
  assert.equal(node('error-message').textContent,message);
  assert.equal(node('error').hidden,false);
  assert.equal(calls.filter(([path])=>path==='/api/missed-shift').length,1);
});

test('validator violations are successful reports, not failed HTTP actions', async () => {
  const {readFile} = await import('node:fs/promises');
  const vm = await import('node:vm');
  const {responseFailure} = await import('./static/time.mjs');
  const nodes = new Map();
  const node = id => {if(!nodes.has(id)) nodes.set(id,{textContent:'',hidden:true,disabled:false,checked:false,lastChild:{textContent:''},setAttribute(){}});return nodes.get(id);};
  const result={code:0,state:{pending:null,shifts:[]},settings:{restScheme:1},metadataRevision:2,
    classifications:{},pendingKind:null,report:{validatorCode:101,status:'violation'}};
  const context=vm.createContext({document:{getElementById:node,querySelectorAll:()=>[]},responseFailure,Intl,
    render(){},fetch:async()=>({ok:true,status:200,json:async()=>result})});
  const source=await readFile(new URL('./static/app.js',import.meta.url),'utf8');
  context.browserRequest=async (path,data)=>context.fetch(`/api/${path}`,data===undefined?{cache:'no-store'}:{method:'POST',body:JSON.stringify(data)});
  vm.runInContext(source.slice(source.indexOf('const $'),source.indexOf('function tick()'))+'\nglobalThis.api={request};',context);
  assert.equal((await context.api.request('compliance',{start:'',end:''})).report.validatorCode,101);
});

test('start and stop send attendance, regular overtime and timezone without changing timestamps', async () => {
  const {readFile} = await import('node:fs/promises');
  const vm = await import('node:vm');
  const {responseFailure} = await import('./static/time.mjs');
  const nodes = new Map();
  const node = id => {if(!nodes.has(id))nodes.set(id,{textContent:'',hidden:true,disabled:false,checked:false,lastChild:{textContent:''},setAttribute(){}});return nodes.get(id);};
  let saved={pending:null,shifts:[]};const calls=[];
  const context=vm.createContext({document:{getElementById:node,querySelectorAll:()=>[]},responseFailure,Intl,
    localTimestamp:()=> '2026-11-12T10:00',render(){},fetch:async(path,options)=>{
      calls.push([path,options]);
      if(path==='/api/start')saved={pending:100,shifts:[]};
      if(path==='/api/stop')saved={pending:null,shifts:[[100,101]]};
      return {ok:true,status:200,json:async()=>({code:0,state:saved})};
    }});
  const source=await readFile(new URL('./static/app.js',import.meta.url),'utf8');
  context.browserRequest=async (path,data)=>context.fetch(`/api/${path}`,data===undefined?{cache:'no-store'}:{method:'POST',body:JSON.stringify(data)});
  vm.runInContext(source.slice(source.indexOf('const $'),source.indexOf('function tick()'))+'\nglobalThis.api={refresh,change};',context);
  await context.api.refresh();await context.api.change('start');
  node('attendance-time').checked=true;
  node('overtime').checked=true;
  await context.api.change('stop');
  const starts=JSON.parse(calls.find(([p])=>p==='/api/start')[1].body);
  const stops=JSON.parse(calls.find(([p])=>p==='/api/stop')[1].body);
  assert.equal(starts.attendance,false);assert.equal(stops.attendance,true);
  assert.equal(starts.overtime,false);assert.equal(stops.overtime,true);
  assert.equal(starts.timestamp,'2026-11-12T10:00');assert.equal(stops.timestamp,starts.timestamp);
  assert.equal(typeof starts.timeZone,'string');
});

test('older servers explain missing compliance routes', async () => {
  const {responseFailure}=await import('./static/time.mjs');
  assert.match(responseFailure(404,'compliance',{}).message,/does not support compliance checking/);
  assert.match(responseFailure(404,'settings',{}).message,/working-time metadata/);
});

test('hosted shared-demo disclosure follows the server response', async () => {
  const {readFile}=await import('node:fs/promises');const vm=await import('node:vm');
  const {responseFailure}=await import('./static/time.mjs');
  const nodes=new Map();const node=id=>{if(!nodes.has(id))nodes.set(id,{hidden:true,setAttribute(){}});return nodes.get(id);};
  let demo=true;
  const context=vm.createContext({document:{getElementById:node},responseFailure,Intl,render(){},fetch:async()=>({ok:true,status:200,json:async()=>({code:0,state:{pending:null,shifts:[]},demo})})});
  const source=await readFile(new URL('./static/app.js',import.meta.url),'utf8');
  context.browserRequest=async (path,data)=>context.fetch(`/api/${path}`,data===undefined?{cache:'no-store'}:{method:'POST',body:JSON.stringify(data)});
  vm.runInContext(source.slice(source.indexOf('const $'),source.indexOf('function tick()'))+'\nglobalThis.api={request};',context);
  await context.api.request('state');assert.equal(node('demo-notice').hidden,false);
  demo=false;await context.api.request('state');assert.equal(node('demo-notice').hidden,true);
});


test('overlapping violation windows group transitively and preserve every original', async () => {
  const {groupViolations}=await import('./static/time.mjs');
  const rows=[{rule:106,code:106,start:20,end:40},{rule:106,code:106,start:0,end:15},{rule:106,code:106,start:10,end:25}];
  const before=JSON.stringify(rows);
  const groups=groupViolations(rows);
  assert.equal(groups.length,1);assert.equal(groups[0].start,0);assert.equal(groups[0].end,40);
  assert.equal(groups[0].windows.length,3);assert.equal(JSON.stringify(rows),before);
  assert.ok(groups[0].windows.includes(rows[0]));
});
test('different rules, incomplete results and touching windows remain distinct', async () => {
  const {groupViolations}=await import('./static/time.mjs');
  const groups=groupViolations([{rule:106,code:106,start:0,end:20},{rule:106,code:106,start:20,end:40},
    {rule:102,code:102,start:0,end:20},{rule:106,code:21,start:0,end:20},{rule:106,code:21,start:1,end:21}]);
  assert.equal(groups.length,5);assert.equal(groups.filter(g=>g.code===21).length,2);
});
test('hours and worst-window summaries retain the direction of each limit', async () => {
  const {hours,findingExplanation,worstWindow}=await import('./static/time.mjs');
  assert.equal(hours(1440),'24 hours');assert.equal(hours(60),'1 hour');assert.equal(hours(90),'1.5 hours');
  assert.match(findingExplanation({code:106,measured:1440,limit:480}),/24 hours.*8 hours/);
  assert.match(findingExplanation({code:102,measured:600,limit:660}),/10 hours.*11 hours/);
  assert.equal(worstWindow([{code:102,measured:600},{code:102,measured:300}]).measured,300);
  assert.equal(worstWindow([{code:103,measured:1,limit:2},{code:103,measured:0,limit:2}]).measured,0);
  assert.equal(worstWindow([{code:106,measured:1000,limit:480},{code:106,measured:1440,limit:480}]).measured,1440);
  const weekly=[{rule:101,code:101,start:0,end:100,measured:10,limit:1},{rule:101,code:101,start:1,end:101,measured:11,limit:1}];
  const {groupViolations}=await import('./static/time.mjs');
  assert.deepEqual(groupViolations(weekly)[0].windows.map(f=>[f.start,f.end]),[[0,100],[1,101]]);
});
