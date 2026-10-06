#!/usr/bin/env python3
"""restaurants.json 을 Supabase SQL Editor 에 붙여 넣을 upsert 문으로 나눈다.

    python3 scripts/make-upsert.py   # research/upsert-N.sql 을 다시 만든다

SQL Editor 에 한 번에 넣기 좋은 크기(약 24KB)로 나눈다. 기존 행은 data 를 새 값으로 덮고,
목록에서 빠진 행은 지우지 않는다.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / "research"
SOURCE = RESEARCH / "restaurants.json"
CHUNK_BYTES = 24_000

rows = json.loads(SOURCE.read_text())
values = []
for r in rows:
    data = json.dumps(r, ensure_ascii=False, separators=(",", ":")).replace("'", "''")
    ident = r["id"].replace("'", "''")
    values.append(f"('{ident}','{data}'::jsonb,true)")

head = "insert into public.restaurants(id,data,active) values\n"
tail = "\non conflict (id) do update set data = excluded.data, active = excluded.active, updated_at = now();\n"
chunks, current = [], []
for v in values:
    if current and len((",\n".join(current + [v])).encode()) > CHUNK_BYTES:
        chunks.append(current)
        current = []
    current.append(v)
if current:
    chunks.append(current)

for old in RESEARCH.glob("upsert-*.sql"):
    old.unlink()
for i, chunk in enumerate(chunks):
    (RESEARCH / f"upsert-{i}.sql").write_text(head + ",\n".join(chunk) + tail)
print(f"{len(rows)}곳 → upsert-0..{len(chunks) - 1}.sql")
