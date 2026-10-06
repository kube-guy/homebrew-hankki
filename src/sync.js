import { createClient } from '@supabase/supabase-js';

const $ = id => document.getElementById(id);
const config = window.HANKKI_CONFIG || {};
const bridge = window.HankkiState;
let client, user, connected = false, running = false, pending = [], batch = null, baseline, generation = 0;
let activeRun = null;
const copy = value => JSON.parse(JSON.stringify(value));
function status(message) { $('syncStatus').textContent = message; }
function read(key, fallback) { try { return JSON.parse(localStorage.getItem(key)) || fallback; } catch { return fallback; } }
function persist() {
  if (!user) return;
  localStorage.setItem('hankki-queue-' + user.id, JSON.stringify({ pending, batch }));
}
function toMap(state) {
  const items = {};
  for (const name of state.pantry) items[name] = 'today';
  for (const name of state.staples) items[name] = 'staple';
  return { items, favorites: Object.fromEntries(state.favorites.map(id => [id, true])) };
}
function changesBetween(before, after) {
  const a = toMap(before), b = toMap(after), changes = [];
  for (const key of new Set([...Object.keys(a.items), ...Object.keys(b.items)])) {
    if (a.items[key] !== b.items[key]) changes.push({ kind: 'ingredient', key, value: b.items[key] || 'deleted' });
  }
  for (const key of new Set([...Object.keys(a.favorites), ...Object.keys(b.favorites)])) {
    if (a.favorites[key] !== b.favorites[key]) changes.push({ kind: 'favorite', key, value: b.favorites[key] ? 'saved' : 'deleted' });
  }
  return changes;
}
function applyOps(row, changes) {
  const result = { items: { ...(row?.items || {}) }, favorites: { ...(row?.favorites || {}) } };
  for (const op of changes) {
    const target = op.kind === 'ingredient' ? result.items : result.favorites;
    if (op.value === 'deleted') delete target[op.key];
    else target[op.key] = op.kind === 'ingredient' ? op.value : true;
  }
  return result;
}
function renderRow(row) {
  const state = {
    pantry: Object.entries(row.items).filter(([,v]) => v === 'today').map(([k]) => k),
    staples: Object.entries(row.items).filter(([,v]) => v === 'staple').map(([k]) => k),
    favorites: Object.keys(row.favorites).filter(k => row.favorites[k]),
  };
  baseline = copy(state);
  bridge.replace(state);
}
async function synchronize() {
  if (!connected || !user || running || !navigator.onLine) return;
  running = true;
  const current = generation, id = user.id;
  try {
    status('동기화 중…');
    if (!batch && pending.length) {
      batch = { id: crypto.randomUUID(), changes: pending.splice(0, 500) };
      persist();
    }
    let row;
    if (batch) {
      const result = await client.rpc('apply_hankki_changes', { p_request_id: batch.id, p_changes: batch.changes });
      if (result.error) throw result.error;
      if (current !== generation) return;
      row = Array.isArray(result.data) ? result.data[0] : result.data;
      batch = null;
      persist();
    } else {
      const result = await client.from('hankki_state').select('items,favorites,revision').eq('user_id', id).maybeSingle();
      if (result.error) throw result.error;
      if (current !== generation) return;
      row = result.data || { items: {}, favorites: {} };
    }
    renderRow(applyOps(row, pending));
    status(pending.length ? '변경 사항 전송 대기 중' : '동기화됨 · ' + new Date().toLocaleTimeString('ko-KR', {hour:'2-digit',minute:'2-digit'}));
  } catch (error) {
    if (current === generation) status('동기화 대기 · 기기에 저장했어요. 연결 후 다시 시도합니다.');
    console.warn('Hankki sync:', error.code || error.name || 'network error');
  } finally {
    running = false;
  }
}
function syncNow() { activeRun = synchronize(); return activeRun; }
async function activate(session) {
  const id = session?.user?.id || null;
  if (user?.id === id && connected) return;
  generation++;
  connected = false;
  if (activeRun) await activeRun;
  user = session?.user || null;
  $('syncLoginForm').hidden = !!user;
  $('syncActions').hidden = !user;
  if (!user) { status('이 기기에 저장 중'); return; }
  const queue = read('hankki-queue-' + user.id, { pending: [], batch: null });
  pending = queue.pending; batch = queue.batch;
  baseline = copy(bridge.get());
  status('로그인됨 · 동기화 방법을 골라 주세요');
  $('syncChoice').hidden = false;
  $('syncEmailLabel').textContent = user.email || '로그인됨';
  const owner = localStorage.getItem('hankki-sync-owner');
  if (owner === user.id) { connected = true; $('syncChoice').hidden = true; await syncNow(); }
}
async function chooseSync(merge) {
  if (!user) return;
  if (merge) {
    pending.push(...changesBetween({pantry:[],staples:[],favorites:[]}, bridge.get()));
  }
  persist();
  localStorage.setItem('hankki-sync-owner', user.id);
  baseline = copy(bridge.get());
  connected = true;
  $('syncChoice').hidden = true;
  await syncNow();
}
window.addEventListener('hankki:change', () => {
  if (!connected || !user) return;
  const next = bridge.get();
  const changes = changesBetween(baseline, next);
  if (!changes.length) return;
  pending.push(...changes);
  baseline = copy(next);
  try { persist(); } catch { status('저장 공간이 부족해 동기화를 중단했어요.'); connected = false; return; }
  void syncNow();
});
$('syncOpen').onclick = () => $('syncDialog').showModal();
$('syncClose').onclick = () => $('syncDialog').close();
$('syncMerge').onclick = () => void chooseSync(true);
$('syncUseCloud').onclick = () => void chooseSync(false);
$('syncRetry').onclick = () => void syncNow();
$('syncLogout').onclick = async () => {
  if (pending.length || batch) { status('전송할 변경 사항이 남아 있어요. 동기화가 끝난 후 로그아웃해 주세요.'); return; }
  connected = false; generation++;
  if (activeRun) await activeRun;
  await client.auth.signOut({scope:'local'});
  user = null; pending = []; batch = null;
  localStorage.removeItem('hankki-sync-owner');
  bridge.replace({pantry:[],staples:[],favorites:[]});
  $('syncLoginForm').hidden = false; $('syncActions').hidden = true; $('syncChoice').hidden = true;
  status('로그아웃됨 · 이 기기의 재료를 비웠어요');
};
$('syncLoginForm').onsubmit = async event => {
  event.preventDefault();
  if (!client) return;
  $('syncSend').disabled = true;
  const {error} = await client.auth.signInWithOtp({ email:$('syncEmail').value.trim(), options:{emailRedirectTo:location.origin + '/'} });
  $('syncSend').disabled = false;
  status(error ? '로그인 메일을 보내지 못했어요. 잠시 뒤 다시 시도해 주세요.' : '이메일의 로그인 링크를 열어 주세요.');
};
if (!config.supabaseUrl || !config.supabasePublishableKey) {
  status('기기 저장 · 클라우드 연결 준비 중');
  $('syncSend').disabled = true;
  $('syncSetupNote').hidden = false;
} else {
  client = createClient(config.supabaseUrl, config.supabasePublishableKey);
  client.auth.onAuthStateChange((event, session) => { if (event !== 'TOKEN_REFRESHED') setTimeout(() => void activate(session), 0); });
  void client.auth.getSession().then(({data}) => activate(data.session));
  setInterval(() => { if (!document.hidden) void syncNow(); }, 10000);
  window.addEventListener('online', () => void syncNow());
  window.addEventListener('focus', () => void syncNow());
  window.addEventListener('offline', () => status('오프라인 · 변경 사항은 이 기기에 저장 중'));
}
