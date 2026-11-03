import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';

test('canvas image fetch stops reading an oversized stream before buffering it all',async()=>{
 const server=createServer((_req,res)=>{res.writeHead(200,{'Content-Type':'image/png'});res.write(Buffer.alloc(64));});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const prior=process.env.LOOKD_URL;process.env.LOOKD_URL=`http://127.0.0.1:${server.address().port}`;
 try{
  const {fetchBytes}=await import('./lookd.mjs?bounded-stream-test');
  await assert.rejects(fetchBytes('/image',{maxBytes:32,signal:AbortSignal.timeout(1000)}),/图像超过/);
 }finally{if(prior===undefined)delete process.env.LOOKD_URL;else process.env.LOOKD_URL=prior;server.closeAllConnections();await new Promise(r=>server.close(r));}
});
