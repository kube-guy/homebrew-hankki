const {test}=require('node:test');
const assert=require('node:assert/strict');
const {parse,apply}=require('../dist/pantry-language.js');
test('mixed Korean requests and aliases',()=>{
 const out=apply({pantry:['우유'],staples:[]},parse('당근이랑 양파 추가하고, 우유는 다 먹었어. 계란은 항상 있어'));
 assert.deepEqual(new Set(out.pantry),new Set(['당근','양파']));assert.deepEqual(out.staples,['달걀']);
});
test('quantities and exact ingredients do not overlap',()=>{
 assert.deepEqual(new Set(parse('사과 2개와 오이 3개 추가해줘').map(x=>x.ingredient)),new Set(['사과','오이']));
 assert.deepEqual(parse('참기름 추가해줘'),[{ingredient:'참기름',action:'add'}]);
});
test('staple removal and moving back to daily ingredients',()=>{
 assert.deepEqual(apply({pantry:[],staples:['달걀']},parse('달걀은 상시 재료에서 빼줘')).pantry,['달걀']);
 assert.deepEqual(apply({pantry:[],staples:['달걀']},parse('달걀 다 먹었어')).staples,[]);
});
test('negative, conditional, questions and conflicting input fail without mutation',()=>{
 for(const text of ['우유 추가하지 마','당근 빼지마','우유가 있어?','당근 있으면 넣어줘','당근 추가하고 당근 삭제해줘','양파 추가하고 우유는 나중에 살 거야'])assert.throws(()=>parse(text),text);
});
test('custom food names and persisted names',()=>{
 assert.deepEqual(parse('콜라비 추가해줘'),[{ingredient:'콜라비',action:'add'}]);
 assert.deepEqual(parse('루콜라는 항상 있어',['루콜라']),[{ingredient:'루콜라',action:'staple'}]);
});
