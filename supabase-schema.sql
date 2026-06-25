-- ============================================================
-- HappySprout Phase 1 — Supabase Database Schema
-- Run this in Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- 1. PROFILES TABLE (extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT,
  display_name TEXT DEFAULT '',
  role        TEXT DEFAULT 'parent' CHECK (role IN ('parent', 'child')),
  parent_id   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  avatar      TEXT DEFAULT '🐱',
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- 2. PROGRESS TABLE (video watch + quiz scores)
CREATE TABLE IF NOT EXISTS public.progress (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  video_id    TEXT NOT NULL,
  watched_at  TIMESTAMPTZ DEFAULT now(),
  quiz_score  INT DEFAULT 0,
  quiz_total  INT DEFAULT 0,
  watch_time_seconds INT DEFAULT 0,
  UNIQUE(user_id, video_id)
);

-- 3. BADGES TABLE
CREATE TABLE IF NOT EXISTS public.badges (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_slug  TEXT NOT NULL,
  earned_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, badge_slug)
);

-- 4. DAILY_LIMITS TABLE (parent settings per child)
CREATE TABLE IF NOT EXISTS public.daily_limits (
  id              BIGSERIAL PRIMARY KEY,
  child_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  max_minutes     INT DEFAULT 60,
  block_start     TEXT DEFAULT '21:00',
  block_end       TEXT DEFAULT '07:00',
  block_enabled   BOOLEAN DEFAULT false,
  hidden_videos   TEXT[] DEFAULT '{}',
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(child_id)
);

-- 5. DAILY_ACTIVITY TABLE (for learning reports)
CREATE TABLE IF NOT EXISTS public.daily_activity (
  id              BIGSERIAL PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  activity_date   DATE NOT NULL DEFAULT CURRENT_DATE,
  watch_seconds   INT DEFAULT 0,
  videos_watched  INT DEFAULT 0,
  stars_earned    INT DEFAULT 0,
  UNIQUE(user_id, activity_date)
);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_activity ENABLE ROW LEVEL SECURITY;

-- Profiles: users can see/edit their own profile; parents can see children's
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Parents can view children" ON public.profiles FOR SELECT USING (
  auth.uid() = parent_id
);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Progress: users manage their own; parents view children's
CREATE POLICY "Users can view own progress" ON public.progress FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own progress" ON public.progress FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own progress" ON public.progress FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Parents view child progress" ON public.progress FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = user_id AND p.parent_id = auth.uid())
);

-- Badges: same pattern
CREATE POLICY "Users can view own badges" ON public.badges FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own badges" ON public.badges FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Parents view child badges" ON public.badges FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = user_id AND p.parent_id = auth.uid())
);

-- Daily limits: parent sets for child
CREATE POLICY "Users view own limits" ON public.daily_limits FOR SELECT USING (auth.uid() = child_id);
CREATE POLICY "Parents view child limits" ON public.daily_limits FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = child_id AND p.parent_id = auth.uid())
);
CREATE POLICY "Users update own limits" ON public.daily_limits FOR UPDATE USING (auth.uid() = child_id);
CREATE POLICY "Parents update child limits" ON public.daily_limits FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = child_id AND p.parent_id = auth.uid())
);
CREATE POLICY "Users insert own limits" ON public.daily_limits FOR INSERT WITH CHECK (auth.uid() = child_id);

-- Daily activity: same pattern
CREATE POLICY "Users view own activity" ON public.daily_activity FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users insert own activity" ON public.daily_activity FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own activity" ON public.daily_activity FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Parents view child activity" ON public.daily_activity FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = user_id AND p.parent_id = auth.uid())
);

-- ============================================================
-- TRIGGER: Auto-create profile on signup
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'display_name', ''));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- Done! Tables created with RLS policies.
-- ============================================================
