-- Columna para rastrear si ya se envió el recordatorio 1h antes
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_sent_at timestamptz;
