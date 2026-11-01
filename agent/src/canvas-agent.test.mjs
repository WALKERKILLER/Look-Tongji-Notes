// Protocol fixtures exercise orchestration, not successful real-model inference.
import test from 'node:test';
import assert from 'node:assert/strict';
import { CanvasRunner, CanvasToolScope, CANVAS_TOOLS } from './canvas-agent.mjs';
import { seeCanvasImages } from './vision.mjs';

const context=()=>({workspace_id:'L',revision:7,object_ids:['pdf','generated'],editable_ids:['generated'],sources:[
 {id:'pdf-selection',label:'Real parser fixture · p3',kind:'pdf',availability:'text',text:'计算 cache miss 的代价。',anchor:{id:'pdf-selection',workspace_id:'L',object_id:'pdf',kind:'pdf',document_id:'doc',page:3,start:10,end:30,fingerprint:'abc'}},
 {id:'video-window',label:'Lecture',kind:'video',availability:'timestamped_transcript',text:'[512000–550000 ms] 缓存失效时需要读取主存。',anchor:{id:'video-window',workspace_id:'L',object_id:'lecture',kind:'video',time_start_ms:512000,time_end_ms:550000}},
 {id:'ink',label:'Handwriting',kind:'ink',availability:'vision_required',text:'',anchor:{id:'ink',workspace_id:'L',object_id:'pdf',kind:'ink',region:[.1,.2,.3,.3],stroke_ids:['stroke']}}
]});
const blocks=[{type:'heading',text:'缓存失效'},{type:'table',columns:['事件','操作'],rows:[['miss','读取主存']]},{type:'exercise',text:'为什么 miss 更慢？',hint:'比较访问路径',answer:'需要访问下一层存储。'}];
test('scope exposes only reads and rejects every former canvas write tool',async()=>{
 const scope=new CanvasToolScope(context());
 assert.deepEqual(CANVAS_TOOLS.map(t=>t.name),['get_canvas_context','read_document_selection','get_video_context','inspect_canvas_region']);
 await scope.execute('read_document_selection',{source_id:'pdf-selection'});
 for(const name of ['create_canvas_card','update_canvas_card','create_connection','focus_source','replace_canvas']) {
  await assert.rejects(scope.execute(name,{kind:'note',title:'x',blocks,source_ids:['pdf-selection'],object_id:'generated',from:'pdf',to:'generated',label:'x'}),/未授权/);
 }
 await assert.rejects(scope.execute('read_document_selection',{source_id:'unselected-secret'}),/上下文/);
 assert.deepEqual(scope.operations,[]);
});
test('unavailable visual input never grants citation credit',async()=>{
 const scope=new CanvasToolScope(context());await scope.execute('inspect_canvas_region',{source_id:'ink'});
 assert(!scope.seen.has('ink'));
 const observed=new CanvasToolScope(context(),{visual:async()=>({mode:'image',content:[{type:'image',data:'fixture-pixels',mimeType:'image/png'}]})});
 const r=await observed.execute('inspect_canvas_region',{source_id:'ink'});
 assert.equal(r.content[1].type,'image');assert(observed.seen.has('ink'));
});
const message=(content,stopReason='toolUse')=>({role:'assistant',content,stopReason,model:'protocol-fixture',provider:'test',timestamp:Date.now(),usage:{}});
const tool=(id,name,args={})=>({type:'toolCall',id,name,arguments:args});
async function settled(runner,id){for(let i=0;i<80;i++){const s=runner.status(id);if(['done','error','cancelled'].includes(s.state))return s;await new Promise(r=>setTimeout(r,5));}throw new Error('fixture timed out');}
test('tool loop keeps answers in chat and rejects hallucinated write calls',async()=>{
 let turn=0;const requests=[];
 const pipeline={currentModel:async()=>({id:'protocol-fixture'}),runtime:{completeSimple:async(_m,c)=>{
  turn++;if(turn===1)return message([tool('a','get_canvas_context'),tool('b','read_document_selection',{source_id:'pdf-selection'}),tool('c','get_video_context',{source_id:'video-window'})]);
  if(turn===2){assert(c.messages.some(m=>m.role==='toolResult'&&JSON.stringify(m).includes('缓存失效')));return message([tool('d','create_canvas_card',{kind:'explanation',title:'联合解释',blocks,source_ids:['pdf-selection','video-window']})]);}
  assert(c.messages.some(m=>m.role==='toolResult'&&m.toolName==='create_canvas_card'&&m.isError));return message([{type:'text',text:'解释保留在对话中。'}],'stop');
 }}};
 const runner=new CanvasRunner(pipeline,{call:async(...args)=>{requests.push(args);return context();}});
 const start=await runner.start({lecture_id:'L',question:'结合老师讲解解释选区',selection:{revision:7}});
 const r=await settled(runner,start.id);assert.equal(r.state,'done');assert.equal(r.operations.length,0);
 assert.equal(requests.length,1);assert.equal(requests[0][0],'POST');assert(requests[0][1].endsWith('/context'));
 assert.equal(r.sources[0].page,3);assert.deepEqual(r.sources.map(s=>s.id),['pdf-selection','video-window']);assert.match(r.answer,/对话/);
});
test('cancellation aborts an active provider request without canvas operations',async()=>{
 let calls=0;let entered;const active=new Promise(r=>entered=r);
 const pipeline={currentModel:async()=>({id:'fixture'}),runtime:{completeSimple:async(_m,_c,{signal})=>{
  if(++calls===1)return message([tool('r','read_document_selection',{source_id:'pdf-selection'}),tool('n','create_canvas_card',{kind:'note',title:'pending',blocks,source_ids:['pdf-selection']})]);
  entered();await new Promise((_,reject)=>signal.addEventListener('abort',()=>reject(signal.reason),{once:true}));
 }}};
 const runner=new CanvasRunner(pipeline,{call:async()=>context()});const start=await runner.start({lecture_id:'L',question:'cancel fixture',selection:{}});
 await active;const r=await runner.cancel(start.id);assert.equal(r.state,'cancelled');assert.deepEqual(r.operations,[]);
});
test('no configured model is an explicit error, and text-only vision never pretends to see',async()=>{
 const runner=new CanvasRunner({currentModel:async()=>null},{call:async()=>context()});
 const start=await runner.start({lecture_id:'L',question:'解释',selection:{}});const r=await settled(runner,start.id);
 assert.equal(r.state,'error');assert.match(r.error,/配置模型/);assert.deepEqual(r.operations,[]);
 const vision=await seeCanvasImages({currentModel:async()=>({input:['text']}),visionModel:async()=>null},[{label:'selected pixels',img:{bytes:Buffer.from('pixels'),mimeType:'image/png'}}]);
 assert.equal(vision.mode,'unavailable');assert(vision.content.every(c=>c.type==='text'));
});

test('cancellation completes even if the provider ignores abort, and late output is never applied',async()=>{
 let entered,finish;const active=new Promise(r=>entered=r);
 const pipeline={currentModel:async()=>({id:'fixture'}),runtime:{completeSimple:async()=>{entered();return new Promise(r=>finish=r);}}};
 const runner=new CanvasRunner(pipeline,{call:async()=>context()});
 const start=await runner.start({lecture_id:'L',question:'cancel ignored signal',selection:{}});
 await active;
 const cancelled=await Promise.race([runner.cancel(start.id),new Promise((_,reject)=>setTimeout(()=>reject(new Error('cancel stalled')),100))]);
 assert.equal(cancelled.state,'cancelled');assert.deepEqual(cancelled.operations,[]);
 finish(message([{type:'text',text:'late provider result'}],'stop'));
 await new Promise(r=>setTimeout(r,0));assert.equal(runner.status(start.id).state,'cancelled');
});
test('provider errors never expose keys and tool budgets discard all staged changes',async()=>{
 const failing=new CanvasRunner({currentModel:async()=>({id:'fixture'}),runtime:{completeSimple:async()=>{throw new Error('secret-key-123 provider HTTP error');}}},{call:async()=>context()});
 const a=await failing.start({lecture_id:'L',question:'error fixture',selection:{}}),error=await settled(failing,a.id);
 assert.equal(error.state,'error');assert(!JSON.stringify(error).includes('secret-key-123'));
 const looping=new CanvasRunner({currentModel:async()=>({id:'fixture'}),runtime:{completeSimple:async()=>message(Array.from({length:21},(_,i)=>tool(String(i),'get_canvas_context')))}},{call:async()=>context()});
 const b=await looping.start({lecture_id:'L',question:'budget fixture',selection:{}}),exceeded=await settled(looping,b.id);
 assert.equal(exceeded.state,'error');assert.match(exceeded.error,/20次/);assert.deepEqual(exceeded.operations,[]);
});

// Scope identity excludes camera/layout revision, but includes exact ranges and content fingerprints.
import {canvasContextKey, conversationMessages} from './canvas-agent.mjs';
test('conversation history never reintroduces removed or changed references',()=>{
 const original=context(),key=canvasContextKey(original);
 const turns=[{state:'done',context_key:key,question:'q',answer:'a'},{state:'error',context_key:key,question:'failed',answer:''}];
 assert.equal(conversationMessages(turns,key).length,2);
 original.revision++;assert.equal(canvasContextKey(original),key);
 original.sources.pop();assert.equal(conversationMessages(turns,canvasContextKey(original)).length,0);
 original.sources[0].anchor.start++;assert.notEqual(canvasContextKey(original),key);
});
test('video tool prepares only its bound source and cites actual returned transcript',async()=>{
 const ctx=context();ctx.sources[1].text='';let requested=[];
 const scope=new CanvasToolScope(ctx,{prepareVideo:async(s)=>{requested.push(s.id);s.text='[512000–550000 ms] Actual decoder output';s.availability='timestamped_transcript';}});
 await scope.execute('get_video_context',{source_id:'video-window'});
 assert.deepEqual(requested,['video-window']);assert(scope.seen.has('video-window'));
 await assert.rejects(scope.execute('get_video_context',{source_id:'other-video'}),/来源不在/);
});
