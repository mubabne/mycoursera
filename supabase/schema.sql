-- MyCoursera schema v1
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Every table is private to the signed-in user via row-level security (RLS).

-- ---------------------------------------------------------------- courses
create table if not exists public.courses (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title         text not null,
  kind          text not null default 'self' check (kind in ('self', 'university')),
  goal          text not null default '',
  weekly_hours  numeric not null default 6 check (weekly_hours > 0),
  status        text not null default 'active' check (status in ('active', 'paused', 'done')),
  created_at    timestamptz not null default now()
);

-- ------------------------------------------------------------- milestones
create table if not exists public.milestones (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  course_id  uuid not null references public.courses (id) on delete cascade,
  key        text not null,
  title      text not null,
  position   double precision not null default 0,
  archived   boolean not null default false,
  unique (course_id, key)
);

-- ----------------------------------------------------------------- skills
create table if not exists public.skills (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  course_id          uuid not null references public.courses (id) on delete cascade,
  key                text not null,
  name               text not null,
  description        text not null default '',
  status             text not null default 'unassessed'
                     check (status in ('unassessed', 'practicing', 'demonstrated')),
  status_updated_at  timestamptz,
  unique (course_id, key)
);

-- ------------------------------------------------------------- activities
create table if not exists public.activities (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null default auth.uid() references auth.users (id) on delete cascade,
  course_id           uuid not null references public.courses (id) on delete cascade,
  milestone_id        uuid references public.milestones (id) on delete set null,
  key                 text not null,
  title               text not null,
  kind                text not null default 'lesson'
                      check (kind in ('lesson', 'exercise', 'check', 'lab', 'assignment', 'exam', 'project')),
  objective           text not null default '',
  content             text not null default '',
  task                text not null default '',
  criteria            text not null default '',
  est_minutes         integer not null default 30 check (est_minutes > 0),
  position            double precision not null default 0,
  prerequisites       text[] not null default '{}',
  skill_keys          text[] not null default '{}',
  due_at              timestamptz,
  state               text not null default 'not_started'
                      check (state in ('not_started', 'in_progress', 'completed', 'missed')),
  origin              text not null default 'plan' check (origin in ('plan', 'manual', 'adaptive')),
  note                text not null default '',
  source_activity_id  uuid references public.activities (id) on delete set null,
  archived            boolean not null default false,
  completed_at        timestamptz,
  created_at          timestamptz not null default now(),
  unique (course_id, key)
);
create index if not exists activities_course_idx on public.activities (course_id);
create index if not exists activities_due_idx on public.activities (due_at) where due_at is not null;

-- --------------------------------------------------------------- attempts
create table if not exists public.attempts (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  activity_id        uuid not null references public.activities (id) on delete cascade,
  client_attempt_id  uuid not null unique,  -- same id twice = same attempt (no duplicates)
  answer             text not null default '',
  help_level         text not null default 'none'
                     check (help_level in ('none', 'hint', 'explanation', 'worked_solution')),
  verdict            text not null check (verdict in ('pass', 'fail', 'uncertain')),
  evaluated_by       text not null default 'self' check (evaluated_by in ('self', 'ai')),
  feedback           text not null default '',
  gap                text not null default '',
  created_at         timestamptz not null default now()
);
create index if not exists attempts_activity_idx on public.attempts (activity_id);

-- -------------------------------------------------------- tutor_exchanges
create table if not exists public.tutor_exchanges (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  course_id    uuid references public.courses (id) on delete set null,
  activity_id  uuid references public.activities (id) on delete set null,
  help_type    text not null default 'explain',
  question     text not null default '',
  prompt       text not null default '',
  response     text not null default '',
  created_at   timestamptz not null default now()
);
create index if not exists tutor_activity_idx on public.tutor_exchanges (activity_id);

-- ------------------------------------------------------ row-level security
alter table public.courses          enable row level security;
alter table public.milestones       enable row level security;
alter table public.skills           enable row level security;
alter table public.activities       enable row level security;
alter table public.attempts         enable row level security;
alter table public.tutor_exchanges  enable row level security;

drop policy if exists "own rows" on public.courses;
create policy "own rows" on public.courses for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own rows" on public.milestones;
create policy "own rows" on public.milestones for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own rows" on public.skills;
create policy "own rows" on public.skills for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own rows" on public.activities;
create policy "own rows" on public.activities for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own rows" on public.attempts;
create policy "own rows" on public.attempts for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own rows" on public.tutor_exchanges;
create policy "own rows" on public.tutor_exchanges for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
