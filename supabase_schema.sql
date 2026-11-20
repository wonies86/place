-- ============================================================
--  📖 먹고 걷는 사전 · Supabase 스키마
--  Supabase 대시보드 → SQL Editor → New query 에 통째로 붙여넣고 RUN
--  여러 번 실행해도 안전하게 작성했습니다.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1) 표제어(place_entries) — 사전의 한 줄
-- ------------------------------------------------------------
create table if not exists public.place_entries (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,                       -- 표제어: 맛집 이름 / 장소명
  category       text not null default '맛집',        -- 맛집 | 카페 | 명소 | 바·술집 | 놀거리
  region         text default '',                     -- 지역·동네: 성수, 을지로, 교토, 제주 …
  recommend_menu text default '',                     -- 추천 메뉴·볼거리
  visit_month    text default '',                     -- 추천 방문월·시기
  link1_label    text default '',                     -- 인스타그램 | 네이버지도 | 유튜브 | 블로그 | 홈페이지 | 기타
  link1_url      text default '',
  link2_label    text default '',
  link2_url      text default '',
  memo           text default '',                     -- 자유 메모
  author         text default '',                     -- (예전 버전 호환용 · 앱에서는 쓰지 않음, 항상 빈 값)
  status         text not null default '가보자',
  rating         numeric(2,1),                        -- 다녀옴일 때 별점 0~5
  review         text default '',                     -- 다녀온 한 줄 후기
  is_sample      boolean not null default false,      -- 앱의 예시 표제어인지
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- 예전 스키마로 만든 프로젝트에서도 안전하게 칼럼을 더합니다 (재실행 OK)
alter table public.place_entries add column if not exists region         text default '';
alter table public.place_entries add column if not exists recommend_menu text default '';
alter table public.place_entries add column if not exists visit_month    text default '';
alter table public.place_entries add column if not exists link1_label    text default '';
alter table public.place_entries add column if not exists link1_url      text default '';
alter table public.place_entries add column if not exists link2_label    text default '';
alter table public.place_entries add column if not exists link2_url      text default '';
alter table public.place_entries add column if not exists memo           text default '';
-- author: 예전 스키마와의 호환을 위해 칼럼만 남깁니다. 앱은 이 값을 읽지도 쓰지도 않습니다.
alter table public.place_entries add column if not exists author         text default '';
alter table public.place_entries add column if not exists rating         numeric(2,1);
alter table public.place_entries add column if not exists review         text default '';
alter table public.place_entries add column if not exists is_sample      boolean not null default false;

-- 상태는 두 값만. 기존 행이 다른 값을 갖고 있어도 실패하지 않도록 NOT VALID.
alter table public.place_entries drop constraint if exists place_entries_status_chk;
alter table public.place_entries
  add constraint place_entries_status_chk
  check (status in ('가보자', '다녀옴')) not valid;

create index if not exists place_entries_created_idx on public.place_entries (created_at);
create index if not exists place_entries_status_idx  on public.place_entries (status);
create index if not exists place_entries_name_idx    on public.place_entries (name);

-- ------------------------------------------------------------
-- 2) updated_at 자동 갱신
-- ------------------------------------------------------------
create or replace function public.place_dict_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_place_entries_touch on public.place_entries;
create trigger trg_place_entries_touch
  before update on public.place_entries
  for each row execute function public.place_dict_touch_updated_at();

-- ------------------------------------------------------------
-- 3) Row Level Security — 둘만 쓰는 공유 사전
--    "anon key를 가진 사람 = 우리 둘" 이라는 전제입니다.
--    anon key는 페이지에 공개되므로, 주소를 아는 사람은 접근할 수 있어요.
--    더 조이고 싶으면 아래 6)을 참고하세요.
-- ------------------------------------------------------------
alter table public.place_entries enable row level security;

drop policy if exists "place dict read"   on public.place_entries;
drop policy if exists "place dict insert" on public.place_entries;
drop policy if exists "place dict update" on public.place_entries;
drop policy if exists "place dict delete" on public.place_entries;

create policy "place dict read"
  on public.place_entries for select
  to anon, authenticated
  using (true);

create policy "place dict insert"
  on public.place_entries for insert
  to anon, authenticated
  with check (true);

create policy "place dict update"
  on public.place_entries for update
  to anon, authenticated
  using (true) with check (true);

create policy "place dict delete"
  on public.place_entries for delete
  to anon, authenticated
  using (true);

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.place_entries to anon, authenticated;

-- ------------------------------------------------------------
-- 4) Realtime — 한 사람이 적으면 다른 폰에 바로 나타납니다
-- ------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.place_entries;
exception when duplicate_object then null;
end $$;

-- UPDATE/DELETE 이벤트에 이전 값까지 실어 보내기 (선택)
alter table public.place_entries replica identity full;

-- ------------------------------------------------------------
-- 5) (선택) 서버에 예시 표제어를 미리 넣고 싶을 때
--    앱의 "예시 표제어"와 같은 내용입니다. 필요 없으면 건너뛰세요.
-- ------------------------------------------------------------
-- insert into public.place_entries
--   (name, category, region, recommend_menu, visit_month, link1_label, link1_url,
--    memo, status, rating, review, is_sample)
-- values
--   ('금돼지식당', '맛집', '성수', '🥩 삼겹살 · 목살', '🌙 11월', '인스타그램',
--    'https://www.instagram.com/explore/tags/금돼지식당/',
--    '웨이팅이 길다는 소문. 오픈 30분 전에 가서 이름 걸어두기.', '가보자', null, '', true);

-- 예전 버전에서 예시 8개를 넣었다면, 예시만 정리하고 싶을 때:
-- delete from public.place_entries where is_sample and name <> '금돼지식당';

-- 확인용
-- select name, category, region, status, created_at
--   from public.place_entries order by created_at;

-- ------------------------------------------------------------
-- 6) (선택) 더 조이고 싶을 때 — 아래 중 하나만 골라 쓰세요
-- ------------------------------------------------------------
-- ① 초대 코드(room code)로 나누기
--    alter table public.place_entries add column if not exists room_code text not null default 'our-dict';
--    drop policy "place dict read" on public.place_entries;
--    create policy "room read" on public.place_entries for select
--      to anon using (room_code = current_setting('request.headers', true)::json->>'x-room-code');
--    (insert/update/delete 도 같은 조건으로)
--
-- ② Supabase Auth(이메일 매직링크)로 둘만 로그인하게 하기
--    앱에서 supabase.auth.signInWithOtp({ email }) 로 로그인한 뒤
--    정책을 to authenticated + using (auth.uid() is not null) 로 바꿉니다.
--    가장 안전하지만, 두 사람이 각자 한 번씩 로그인해야 합니다.
--
-- ③ 기간 한정으로 쓰고, 끝나면 테이블을 지우거나 정책을 삭제하세요.
