create table public.restaurants (
  id text primary key,
  data jsonb not null check (jsonb_typeof(data) = 'object' and data->>'id' = id),
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.restaurants enable row level security;
create policy catalog_read on public.restaurants for select to authenticated using (active);
grant select on public.restaurants to authenticated;

create table public.lunch_states (
  user_id uuid primary key references auth.users(id),
  state jsonb not null check (jsonb_typeof(state) = 'object' and octet_length(state::text) < 2000000),
  revision integer not null default 1,
  updated_at timestamptz not null default now()
);
alter table public.lunch_states enable row level security;
create policy own_read on public.lunch_states for select to authenticated using ((select auth.uid()) = user_id);
create policy own_insert on public.lunch_states for insert to authenticated with check ((select auth.uid()) = user_id);
create policy own_update on public.lunch_states for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
grant select, insert, update on public.lunch_states to authenticated;

create function public.lunch_catalog() returns jsonb language sql stable security invoker set search_path = '' as $$
  select coalesce(jsonb_agg(data order by id), '[]'::jsonb) from public.restaurants where active;
$$;
revoke all on function public.lunch_catalog() from public, anon;
grant execute on function public.lunch_catalog() to authenticated;

create function public.save_lunch_state(p_state jsonb, p_expected_revision integer)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare new_revision integer;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_expected_revision = 0 then
    insert into public.lunch_states(user_id, state, revision) values(auth.uid(), p_state, 1)
    on conflict do nothing returning revision into new_revision;
  else
    update public.lunch_states set state = p_state, revision = revision + 1, updated_at = now()
    where user_id = auth.uid() and revision = p_expected_revision returning revision into new_revision;
  end if;
  if new_revision is null then raise exception 'revision conflict: local data was not overwritten'; end if;
  return jsonb_build_object('revision', new_revision);
end;
$$;
revoke all on function public.save_lunch_state(jsonb, integer) from public, anon;
grant execute on function public.save_lunch_state(jsonb, integer) to authenticated;
