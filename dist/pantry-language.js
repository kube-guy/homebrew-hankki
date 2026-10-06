/* Local Korean pantry commands: parse the whole message before changing state. */
(function(root){
  'use strict';
  const aliases = {'계란':'달걀','쇠고기':'소고기','닭가슴살':'닭고기','스파게티면':'파스타','파스타면':'파스타','오트':'오트밀'};
  const foods = '밥 쌀 오트밀 파스타 당근 애호박 브로콜리 감자 양파 시금치 단호박 토마토 달걀 두부 닭고기 소고기 연어 바나나 사과 식용유 간장 참기름 우유 치즈 버터 요거트 요구르트 밀가루 설탕 소금 후추 고추장 된장 마늘 대파 쪽파 오이 배추 양배추 고구마 옥수수 완두콩 콩 검은콩 병아리콩 렌틸콩 피망 파프리카 가지 버섯 표고버섯 새송이버섯 팽이버섯 배 딸기 블루베리 귤 오렌지 포도 키위 복숭아 돼지고기 새우 참치 고등어 멸치 김 미역 다시마 국수 빵 떡 올리브유 들기름 깨 두유 생크림 부추 숙주 콩나물 무 시래기 청경채 김치 양송이버섯 콜라비 퀴노아 아보카도 레몬 생강'.split(' ');
  const suffix='(?:해\\s*주세요|해\\s*줘|해주세요|해줘|해요|하고|해주세요|주세요|해|줘|고|요|습니다|다|음)?';
  const rules=[
    ['unstaple',new RegExp('(?:상시\\s*(?:재료)?|기본\\s*재료|항상\\s*(?:있는|두는)\\s*재료)(?:에서|에서는)\\s*(?:빼|제외|삭제|해제)'+suffix,'g')],
    ['staple',new RegExp('(?:항상|늘|언제나)\\s*(?:있(?:어요|어|고|다|음)|두(?:고\\s*있어요|고\\s*있어|는\\s*재료|어요|고|자)|구비(?:해요|해줘|해|하고))','g')],
    ['staple',new RegExp('(?:상시\\s*(?:재료)?|기본\\s*재료|항상\\s*(?:있는|두는)\\s*재료)(?:로|에)?(?:\\s*(?:등록|추가|설정|넣어|해)'+suffix+')?','g')],
    ['remove',new RegExp('(?:다\\s*(?:먹었(?:어요|어|고|다)?|썼(?:어요|어|고|다)?|사용했(?:어요|어|고|다)?)|떨어졌(?:어요|어|고|다)?|없(?:어요|어|고|다|음)|(?:삭제|제거|빼|제외)'+suffix+')','g')],
    ['add',new RegExp('(?:(?:추가|넣어|등록)'+suffix+'|사\\s*왔(?:어요|어|고|다)?|샀(?:어요|어|고|다)?|있(?:어요|어|고|다|음)|남았(?:어요|어|고|다)?)','g')],
  ];
  const escape=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  function ingredientsFrom(text, known){
    const names=[...new Set([...foods,...known,...Object.keys(aliases)])].sort((a,b)=>b.length-a.length);
    const found=[];
    let rest=text.trim().replace(/^(?:(?:그리고|또|그런데|근데|오늘은|오늘|냉장고에|집에|우리집에|지금|이제|재료는)\s*)+/,'');
    // Protect exact food names before stripping Korean particles (e.g. 사과, 오이).
    for(const name of names){
      const re=new RegExp('(^|[\\s,·])'+escape(name)+'(?=(?:은|는|이|가|을|를|도|이랑|랑|하고|과|와)?(?:[\\s,·]|$|[0-9]))','g');
      rest=rest.replace(re,(_,prefix)=>{found.push(aliases[name]||name);return prefix+' ◇ ';});
    }
    rest=rest.replace(/◇\s*(?:이랑|하고|은|는|이|가|을|를|도|과|와|랑)?/g,' ')
      .replace(/\d+(?:\.\d+)?\s*(?:kg|g|ml|l|개|봉지|봉|팩|통|병|모|단|줌|장|알|근|킬로|그램)(?:씩|은|는|을|를|도)?/gi,' ')
      .replace(/(?:^|\s)(?:한|두|세|네)\s*(?:개|봉지|팩|통|병|모|단|줌|장|알)(?:은|는|을|를|도)?(?=\s|$)/g,' ')
      .replace(/(?:^|\s)(?:그리고|또|및|좀|조금|오늘|지금|이제|냉장고에|집에)(?=\s|$)/g,' ');
    const parts=rest.split(/[,·]|\s+(?:그리고|및)\s+|(?:이랑|랑|하고)(?=\s)|\s+/).filter(Boolean);
    for(let part of parts){
      if(/^(은|는|이|가|을|를|도|과|와|랑|이랑|하고)$/.test(part))continue;
      part=part.replace(/(?:은|는|을|를|도)$/,'');
      if(!/^[가-힣A-Za-z]{2,15}$/.test(part)||/(?:주세요|해줘|하지|않|말|없|있|먹|싶|좋|알레르기|전부|모두|전체|재료|항상|상시|기본|늘|구매|나중|내일)/.test(part))throw Error('재료 이름을 분명히 적어 주세요. 예: “당근과 양파 추가해줘”.');
      found.push(aliases[part]||part);
    }
    return [...new Set(found)];
  }
  function parse(text, known=[]){
    text=String(text||'').normalize('NFC').trim();
    if(!text||text.length>500)throw Error('재료 요청을 500자 이내로 적어 주세요.');
    if(/[?？]|하지\s*마|하지\s*말|지\s*마|지\s*말|말고|아니|않|없지|있지|면\s|경우|알레르기|살\s*예정|살\s*거|사야|나중에|내일/.test(text))throw Error('질문·부정·조건이 섞인 문장은 아직 처리하기 어려워요. “당근 추가, 우유 삭제”처럼 적어 주세요. 변경하지 않았어요.');
    const actions=[];let start=0;
    while(start<text.length){
      let hit=null;
      for(const [action,re] of rules){re.lastIndex=start;const match=re.exec(text);if(match&&(!hit||match.index<hit.index||(match.index===hit.index&&match[0].length>hit.length)))hit={action,index:match.index,length:match[0].length};}
      if(!hit)break;
      const subject=text.slice(start,hit.index).replace(/^[\s,.;!\n]+/,'').replace(/(?:그리고|\s고)\s*$/,'');
      const names=ingredientsFrom(subject,known);
      if(!names.length)throw Error('어떤 재료인지 찾지 못했어요. “달걀은 항상 있어”처럼 재료를 먼저 적어 주세요. 변경하지 않았어요.');
      for(const ingredient of names)actions.push({action:hit.action,ingredient});
      start=hit.index+hit.length;
    }
    const tail=text.slice(start).replace(/^[\s,.;!\n]+|[\s,.;!\n]+$/g,'');
    if(!actions.length){for(const ingredient of ingredientsFrom(tail,known))actions.push({action:'add',ingredient});}
    else if(tail&&!/^(?:줘|주세요|해줘|해요|요|고|부탁해|부탁해요)$/.test(tail))throw Error('문장 끝의 요청을 이해하지 못했어요. 재료마다 “추가·삭제·상시 재료로 등록”을 적어 주세요. 변경하지 않았어요.');
    if(!actions.length)throw Error('재료 이름을 적어 주세요.');
    const byName=new Map();for(const a of actions){if(byName.has(a.ingredient)&&byName.get(a.ingredient)!==a.action)throw Error(a.ingredient+'에 서로 다른 요청이 있어요. 한 가지로 적어 주세요. 변경하지 않았어요.');byName.set(a.ingredient,a.action);}
    return [...byName].map(([ingredient,action])=>({ingredient,action}));
  }
  function apply(state,actions){
    const pantry=new Set(state.pantry),staples=new Set(state.staples),changes=[];
    for(const {ingredient,action} of actions){
      const before=staples.has(ingredient)?'staple':pantry.has(ingredient)?'today':'absent';
      if(action==='staple'){staples.add(ingredient);pantry.delete(ingredient);}
      else if(action==='remove'){pantry.delete(ingredient);staples.delete(ingredient);}
      else if(action==='unstaple'){if(staples.delete(ingredient))pantry.add(ingredient);}
      else if(action==='add'){if(!staples.has(ingredient))pantry.add(ingredient);}
      else throw Error('지원하지 않는 요청이에요.');
      const after=staples.has(ingredient)?'staple':pantry.has(ingredient)?'today':'absent';
      changes.push({ingredient,action,before,after});
    }
    return {pantry:[...pantry],staples:[...staples],changes};
  }
  const api={parse,apply};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.PantryLanguage=api;
})(typeof window==='undefined'?globalThis:window);
