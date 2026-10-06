-- 모두에게 적용되는 기본 기준 지점. 사용자가 앱에서 바꾼 지점은 lunch_states.state.origin 에 저장된다.
-- 실제 좌표는 저장소에 두지 않는다. 아래 insert 의 값을 채워 SQL Editor 에서 실행한다.
create table public.lunch_settings (
  key text primary key,
  value jsonb not null check (jsonb_typeof(value) = 'object'),
  updated_at timestamptz not null default now()
);
alter table public.lunch_settings enable row level security;
create policy settings_read on public.lunch_settings for select to authenticated using (true);
grant select on public.lunch_settings to authenticated;

create function public.lunch_default_origin() returns jsonb language sql stable security invoker set search_path = '' as $$
  select value from public.lunch_settings where key = 'default_origin';
$$;
revoke all on function public.lunch_default_origin() from public, anon;
grant execute on function public.lunch_default_origin() to authenticated;

-- 기본 지점 저장·변경 (관리자가 SQL Editor 에서 실행)
-- insert into public.lunch_settings(key, value) values
--   ('default_origin', '{"name": "<지점 이름>", "latitude": <위도>, "longitude": <경도>, "radiusMeters": 1000}')
-- on conflict (key) do update set value = excluded.value, updated_at = now();
