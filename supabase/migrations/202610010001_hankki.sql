begin;
create table if not exists public.hankki_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  items jsonb not null default '{}'::jsonb,
  favorites jsonb not null default '{}'::jsonb,
  revision bigint not null default 0,
  updated_at timestamptz not null default now()
);
create table if not exists public.hankki_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  primary key(user_id, request_id)
);
alter table public.hankki_state enable row level security;
alter table public.hankki_requests enable row level security;
revoke all on public.hankki_state, public.hankki_requests from anon, authenticated;
grant select on public.hankki_state to authenticated;
drop policy if exists "Read own kitchen" on public.hankki_state;
create policy "Read own kitchen" on public.hankki_state for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.apply_hankki_changes(p_request_id uuid, p_changes jsonb)
returns public.hankki_state
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  kitchen public.hankki_state;
  op jsonb;
  item_name text;
  item_value text;
begin
  if uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_request_id is null or p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) > 500 then
    raise exception 'Invalid changes';
  end if;
  insert into public.hankki_state(user_id) values(uid) on conflict do nothing;
  select * into kitchen from public.hankki_state where user_id=uid for update;
  if exists(select 1 from public.hankki_requests where user_id=uid and request_id=p_request_id) then return kitchen; end if;
  for op in select * from jsonb_array_elements(p_changes) loop
    item_name := op->>'key';
    item_value := op->>'value';
    if item_name is null or char_length(item_name) < 1 or char_length(item_name) > 60 then raise exception 'Invalid item'; end if;
    if op->>'kind'='ingredient' then
      if item_value='deleted' then kitchen.items := kitchen.items - item_name;
      elsif item_value in ('today','staple') then kitchen.items := jsonb_set(kitchen.items,array[item_name],to_jsonb(item_value));
      else raise exception 'Invalid ingredient value'; end if;
    elsif op->>'kind'='favorite' then
      if item_value='deleted' then kitchen.favorites := kitchen.favorites - item_name;
      elsif item_value='saved' then kitchen.favorites := jsonb_set(kitchen.favorites,array[item_name],'true'::jsonb);
      else raise exception 'Invalid favorite value'; end if;
    else raise exception 'Invalid change kind'; end if;
  end loop;
  if (select count(*) from jsonb_object_keys(kitchen.items)) > 500 or (select count(*) from jsonb_object_keys(kitchen.favorites)) > 500 then raise exception 'Kitchen size limit reached'; end if;
  update public.hankki_state set items=kitchen.items, favorites=kitchen.favorites, revision=revision+1, updated_at=now() where user_id=uid returning * into kitchen;
  insert into public.hankki_requests(user_id,request_id) values(uid,p_request_id);
  return kitchen;
end;
$$;
revoke all on function public.apply_hankki_changes(uuid,jsonb) from public, anon;
grant execute on function public.apply_hankki_changes(uuid,jsonb) to authenticated;
commit;
