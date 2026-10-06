/* Shopping list: pure helpers over [{name, checked, recipes}] so the UI and tests share one behavior. */
(function(root){
  'use strict';
  const valid=name=>typeof name==='string'&&/^[가-힣A-Za-z]{1,15}$/.test(name);
  function normalize(list){
    if(!Array.isArray(list))return [];
    const seen=new Set();
    return list.filter(i=>i&&valid(i.name)&&!seen.has(i.name)&&seen.add(i.name))
      .map(i=>({name:i.name,checked:i.checked===true,recipes:Array.isArray(i.recipes)?[...new Set(i.recipes.filter(r=>typeof r==='string'))]:[]}));
  }
  function add(list,names,recipe){
    const out=normalize(list),added=[];
    for(const name of names){
      if(!valid(name))throw Error(`‘${name}’은(는) 재료 이름으로 쓸 수 없어요. 한글이나 영문 15자 이내로 적어 주세요.`);
      let item=out.find(i=>i.name===name);
      if(!item){item={name,checked:false,recipes:[]};out.push(item);added.push(name)}
      else if(item.checked){item.checked=false;added.push(name)}
      if(recipe&&!item.recipes.includes(recipe))item.recipes.push(recipe);
    }
    return {list:out,added};
  }
  function toggle(list,name){return normalize(list).map(i=>i.name===name?{...i,checked:!i.checked}:i)}
  function remove(list,name){return normalize(list).filter(i=>i.name!==name)}
  // Bought items move into today's pantry; staples are already on hand so they only leave the list.
  function stock(list,state){
    const items=normalize(list),pantry=new Set(state.pantry),staples=new Set(state.staples),moved=[];
    for(const i of items)if(i.checked){if(!staples.has(i.name))pantry.add(i.name);moved.push(i.name)}
    return {list:items.filter(i=>!i.checked),pantry:[...pantry],staples:[...staples],moved};
  }
  function toText(list){
    const items=normalize(list);
    if(!items.length)return '';
    return ['장보기 목록',...items.map(i=>`${i.checked?'[x]':'[ ]'} ${i.name}${i.recipes.length?` (${i.recipes.join(', ')})`:''}`)].join('\n');
  }
  const api={normalize,add,toggle,remove,stock,toText};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.ShoppingList=api;
})(typeof window==='undefined'?globalThis:window);
