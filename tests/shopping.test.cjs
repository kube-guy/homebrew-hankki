const {test}=require('node:test');
const assert=require('node:assert/strict');
const shop=require('../dist/shopping-list.js');
test('adding merges duplicates and remembers recipes',()=>{
 let {list,added}=shop.add([],['두부','애호박'],'두부 채소 덮밥');
 assert.deepEqual(added,['두부','애호박']);
 ({list,added}=shop.add(list,['두부','간장'],'다른 메뉴'));
 assert.deepEqual(added,['간장']);
 assert.deepEqual(list.find(i=>i.name==='두부').recipes,['두부 채소 덮밥','다른 메뉴']);
 assert.equal(list.length,3);
});
test('re-adding a bought item unchecks it',()=>{
 const list=shop.toggle(shop.add([],['우유']).list,'우유');
 assert.equal(list[0].checked,true);
 const out=shop.add(list,['우유']);
 assert.deepEqual(out.added,['우유']);assert.equal(out.list[0].checked,false);
});
test('invalid names throw without mutation',()=>{
 const list=shop.add([],['당근']).list;
 assert.throws(()=>shop.add(list,['양파','<b>']));
 assert.equal(list.length,1);
});
test('stocking moves checked items to pantry and skips staples',()=>{
 let list=shop.add([],['당근','달걀','양파']).list;
 list=shop.toggle(shop.toggle(list,'당근'),'달걀');
 const out=shop.stock(list,{pantry:['밥'],staples:['달걀']});
 assert.deepEqual(out.moved,['당근','달걀']);
 assert.deepEqual(new Set(out.pantry),new Set(['밥','당근']));
 assert.deepEqual(out.list.map(i=>i.name),['양파']);
});
test('normalize drops corrupted storage and text export',()=>{
 assert.deepEqual(shop.normalize({}),[]);
 const list=shop.normalize([{name:'두부',checked:true,recipes:['덮밥']},{name:'두부'},null,{name:''},{name:'파'}]);
 assert.deepEqual(list.map(i=>i.name),['두부','파']);
 assert.equal(shop.toText(list),'장보기 목록\n[x] 두부 (덮밥)\n[ ] 파');
 assert.equal(shop.toText([]),'');
});
