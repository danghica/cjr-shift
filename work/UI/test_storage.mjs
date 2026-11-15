import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createBrowserTransport,STORE_KEY} from './static/storage.mjs';
function memory(){const values=new Map();return {getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v)};}
function locks(){let tail=Promise.resolve();return {request(_key,_options,work){const next=tail.then(work);tail=next.catch(()=>{});return next;}};}
const snapshot=n=>({version:1,encoding:`state-${n}`,metadata:{revision:n}});
const success=value=>({ok:true,status:200,json:async()=>({code:0,browserStorage:true,snapshot:value,state:{pending:null,shifts:[]}})});
test('each browser saves its own snapshot and sends it on reload',async()=>{
  const a=memory(),b=memory();const sent=[];
  const fetch=async(_url,options)=>{const body=JSON.parse(options.body);sent.push(body);return success(snapshot((body.snapshot?.metadata.revision??0)+1));};
  const requestA=createBrowserTransport({storage:a,locks:locks(),fetch});
  await requestA('start',{overtime:true});await createBrowserTransport({storage:a,locks:locks(),fetch})('state');
  await createBrowserTransport({storage:b,locks:locks(),fetch})('state');
  assert.equal(sent[0].snapshot,null);assert.equal(sent[1].snapshot.metadata.revision,1);assert.equal(sent[2].snapshot,null);
  assert.equal(JSON.parse(a.getItem(STORE_KEY)).metadata.revision,2);assert.equal(JSON.parse(b.getItem(STORE_KEY)).metadata.revision,1);
});
test('tabs coordinate through one lock and read the latest saved state',async()=>{
  const storage=memory(),sharedLocks=locks();const inputs=[];
  const fetch=async(_url,options)=>{let body=JSON.parse(options.body);inputs.push(body.snapshot?.metadata.revision??0);await Promise.resolve();return success(snapshot((body.snapshot?.metadata.revision??0)+1));};
  const a=createBrowserTransport({storage,locks:sharedLocks,fetch}),b=createBrowserTransport({storage,locks:sharedLocks,fetch});
  await Promise.all([a('start'),b('stop')]);assert.deepEqual(inputs,[0,1]);assert.equal(JSON.parse(storage.getItem(STORE_KEY)).metadata.revision,2);
});
test('quota failure rejects a save and preserves the prior snapshot',async()=>{
  const old=JSON.stringify(snapshot(3));const storage={getItem:()=>old,setItem:()=>{throw new Error('quota');}};
  const request=createBrowserTransport({storage,locks:locks(),fetch:async()=>success(snapshot(4))});
  await assert.rejects(request('stop'),/change was not saved/);assert.equal(storage.getItem(STORE_KEY),old);
});
test('invalid or blocked storage is never erased or sent to the server',async()=>{
  let called=false;const fetch=async()=>{called=true;};const storage=memory();storage.setItem(STORE_KEY,'broken');
  await assert.rejects(createBrowserTransport({storage,locks:locks(),fetch})('state'),/kept unchanged/);assert.equal(storage.getItem(STORE_KEY),'broken');
  storage.setItem(STORE_KEY,'null');
  await assert.rejects(createBrowserTransport({storage,locks:locks(),fetch})('state'),/kept unchanged/);assert.equal(storage.getItem(STORE_KEY),'null');
  await assert.rejects(createBrowserTransport({storage:{getItem(){throw new Error();}},locks:locks(),fetch})('state'),/storage is unavailable/);
  assert.equal(called,false);
});
test('domain failures never overwrite browser data and unsupported locking fails clearly',async()=>{
  const storage=memory();const old=JSON.stringify(snapshot(3));storage.setItem(STORE_KEY,old);
  const request=createBrowserTransport({storage,locks:locks(),fetch:async()=>({ok:false,status:409,json:async()=>({code:2})})});
  assert.equal((await request('stop')).status,409);assert.equal(storage.getItem(STORE_KEY),old);
  await assert.rejects(createBrowserTransport({storage,locks:{}})('start'),/Web Locks/);
});
test('unexpected changes and invalid server responses cannot clobber a saved store',async()=>{
  const storage=memory();storage.setItem(STORE_KEY,JSON.stringify(snapshot(1)));
  const request=createBrowserTransport({storage,locks:locks(),fetch:async()=>{storage.setItem(STORE_KEY,JSON.stringify(snapshot(5)));return success(snapshot(2));}});
  await assert.rejects(request('start'),/another tab/);assert.equal(JSON.parse(storage.getItem(STORE_KEY)).metadata.revision,5);
  const bad=createBrowserTransport({storage,locks:locks(),fetch:async()=>({ok:true,status:200,json:async()=>({code:0})})});
  await assert.rejects(bad('start'),/did not return/);assert.equal(JSON.parse(storage.getItem(STORE_KEY)).metadata.revision,5);
});
