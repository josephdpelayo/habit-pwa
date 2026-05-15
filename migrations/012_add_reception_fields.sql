-- Run in Supabase SQL Editor
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS reception_title text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS reception_logo text;
