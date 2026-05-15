-- Fix RLS policies that prevent admin from seeing users
-- Run this in Supabase > SQL Editor

-- 1. Allow all authenticated users to read profiles (admin needs this)
DROP POLICY IF EXISTS "Admin reads all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users read own profile" ON public.profiles;

CREATE POLICY "Authenticated users read profiles"
  ON public.profiles FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- 2. Allow users to update only their own profile
DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Admin updates all profiles" ON public.profiles;

CREATE POLICY "Users update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id OR 
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin');

-- 3. Fix insert policy
DROP POLICY IF EXISTS "Service inserts own profile" ON public.profiles;
DROP POLICY IF EXISTS "Admin inserts profiles" ON public.profiles;

CREATE POLICY "Insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- 4. Allow admin to delete posts
DROP POLICY IF EXISTS "Admin delete posts" ON public.posts;
CREATE POLICY "Admin delete posts"
  ON public.posts FOR DELETE
  USING (auth.uid() = user_id OR 
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin');

-- 5. Allow all authenticated to read posts
DROP POLICY IF EXISTS "Auth read posts" ON public.posts;
CREATE POLICY "Auth read posts"
  ON public.posts FOR SELECT
  USING (auth.uid() IS NOT NULL);

SELECT 'RLS policies fixed' as resultado;
