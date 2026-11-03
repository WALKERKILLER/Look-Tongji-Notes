import test from 'node:test';
import assert from 'node:assert/strict';
import { createTools, GROUPS } from './tools.mjs';

test('NAS tools are read-only, course-scoped and require explicit links', async (t) => {
 const requests=[];
 t.mock.method(globalThis,'fetch',async(url,options)=>{
  const path=new URL(url).pathname;
  requests.push([options.method,path]);
  const value=path==='/api/nas'?{
   online:true,observed_at:'2026-10-24T00:00:00Z',course_links:{OS:'40309',NLP:'other'},
   files:[{id:'os',course:'OS',path:'OS/report.md'},{id:'nlp',course:'NLP',path:'NLP/report.md'}],
   jobs:[{course:'OS',generation_state:'ready',submission_state:'unconfirmed'},{course:'NLP'}],
   deadlines:[{course:'OS'},{course:'NLP'}],services:[],
  }:{text:'source excerpt',file:{path:'OS/report.md'}};
  return new Response(JSON.stringify(value),{status:200});
 });
 assert.deepEqual(GROUPS.nas.tools,['nas_overview','nas_files','read_nas_file']);
 const tools=createTools({kind:'course',course_id:'40309'});
 const tool=(name)=>tools.find(t=>t.name===name);
 const data=async(name,args={})=>JSON.parse((await tool(name).execute('test',args)).content[0].text);
 const overview=await data('nas_overview');
 assert.equal(overview.jobs.length,1);
 assert.equal(overview.jobs[0].submission_state,'unconfirmed');
 assert.equal(overview.deadlines.length,1);
 assert.deepEqual((await data('nas_files')).files.map(f=>f.id),['os']);
 await assert.rejects(()=>data('read_nas_file',{id:'nlp'}),/当前课程/);
 assert.equal((await data('read_nas_file',{id:'os'})).text,'source excerpt');
 const unlinked=createTools({kind:'course',course_id:'unmapped'}).find(t=>t.name==='nas_files');
 await assert.rejects(()=>unlinked.execute('test',{}),/关联/);
 assert.ok(requests.every(([method,path])=>method==='GET'&&!path.includes('/actions/')));
});
