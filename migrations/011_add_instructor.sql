-- Run in Supabase SQL Editor
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_instructor boolean DEFAULT false;
