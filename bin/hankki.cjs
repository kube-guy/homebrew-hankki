#!/usr/bin/env node
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const args = process.argv.slice(2);
if(args.includes('--version')){console.log('hankki 0.2.0');process.exit(0)}
if(args.includes('--help')){console.log('한 끼 꾸러미\n\nhankki              앱을 열고 실행\nhankki --no-open    브라우저를 열지 않고 실행\nhankki --port 4174  다른 포트 사용\nhankki --version   버전 확인\n\n종료: Ctrl+C');process.exit(0)}
const portIndex=args.indexOf('--port');
const port=portIndex<0?4173:Number(args[portIndex+1]);
if(!Number.isInteger(port)||port<1024||port>65535){console.error('포트는 1024–65535 사이의 숫자여야 합니다.');process.exit(1)}
const root = path.resolve(__dirname,'../dist');
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg'};
const server=http.createServer((req,res)=>{
  if(req.method!=='GET'&&req.method!=='HEAD'){res.writeHead(405);res.end();return;}
  const host=req.headers.host;
  if(![`127.0.0.1:${port}`,`localhost:${port}`].includes(host)){res.writeHead(403);res.end('Forbidden host');return;}
  let pathname;try{pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname)}catch{res.writeHead(400);res.end();return;}
  if(pathname==='/health'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({app:'hankki',version:'0.2.0'}));return;}
  const file=path.resolve(root,'.'+(pathname==='/'?'/index.html':pathname));
  if(!file.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
  fs.stat(file,(err,stat)=>{
    if(err||!stat.isFile()){res.writeHead(404);res.end('Not found');return;}
    res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Content-Length':stat.size,'Cache-Control':'no-cache','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});
    if(req.method==='HEAD'){res.end();return;}
    const stream=fs.createReadStream(file);stream.on('error',()=>res.destroy());stream.pipe(res);
  });
});
server.on('error',err=>{console.error(err.code==='EADDRINUSE'?`포트 ${port}가 사용 중입니다. 기존 앱을 열거나 hankki --port ${port+1}을 실행하세요.`:err.message);process.exitCode=1});
server.listen(port,'127.0.0.1',()=>{
  const url=`http://localhost:${port}`;console.log(`한 끼 꾸러미: ${url}\n종료하려면 Ctrl+C를 누르세요.`);
  if(!args.includes('--no-open')){const command=process.platform==='darwin'?'open':process.platform==='win32'?'explorer.exe':'xdg-open';const child=spawn(command,[url],{stdio:'ignore'});child.on('error',()=>console.log('브라우저에서 위 주소를 열어 주세요.'));child.unref();}
});
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
