const MAZ_UTC_OFFSET_H = 7;
const SLOT_DUR = 30;
const BEFORE_MIN = 10;

function parseDS(ds) {
  const [y, m, d] = String(ds || '').split('-').map(Number);
  return { y, m, d };
}

function slotMs(ds, slotIdx) {
  const { y, m, d } = parseDS(ds);
  return Date.UTC(y, m - 1, d, MAZ_UTC_OFFSET_H, 0, 0) + Number(slotIdx || 0) * SLOT_DUR * 60000;
}

function fmtSlot(idx) {
  const slot = ((Number(idx || 0) % 48) + 48) % 48;
  const totalMin = slot * SLOT_DUR;
  const h = String(Math.floor(totalMin / 60)).padStart(2, '0');
  const m = String(totalMin % 60).padStart(2, '0');
  return `${h}:${m}`;
}

function slotLabel(booking) {
  const slotsUsed = Number(booking.slots_used || 3);
  return booking.time_str || `${fmtSlot(booking.start_idx)} - ${fmtSlot(Number(booking.start_idx) + slotsUsed)}`;
}

function accessWindow(booking) {
  const slotsUsed = Number(booking.slots_used || 3);
  const startMs = slotMs(booking.ds, booking.start_idx);
  return {
    opensMs: startMs - BEFORE_MIN * 60000,
    startMs,
    closesMs: startMs + slotsUsed * SLOT_DUR * 60000,
  };
}

module.exports = { MAZ_UTC_OFFSET_H, SLOT_DUR, BEFORE_MIN, slotMs, fmtSlot, slotLabel, accessWindow };
