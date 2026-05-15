-- Run in Supabase SQL Editor
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS reception_guests text;
