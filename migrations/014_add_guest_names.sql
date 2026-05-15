-- Run in Supabase SQL Editor
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS guest_names text;
