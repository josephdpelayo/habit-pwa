const PLANS = {
  i1: { id: 'i1', name: 'Visita del dia', price: 110, credits: 1, days: null, type: 'individual' },
  test_i8_10: { id: 'test_i8_10', name: 'Prueba live 8 visitas', price: 10, credits: 8, days: 30, type: 'individual', allowedEmail: 'josephdpelayo@gmail.com' },
  i8: { id: 'i8', name: 'Pack 8 visitas', price: 439, credits: 8, days: 30, type: 'individual' },
  i12: { id: 'i12', name: 'Pack 12 visitas', price: 559, credits: 12, days: 30, type: 'individual' },
  im: { id: 'im', name: 'Mensualidad', price: 759, credits: 999, days: 30, type: 'individual' },
  g1: { id: 'g1', name: 'Sesion grupal', price: 399, credits: 1, days: null, type: 'grupal' },
  g8: { id: 'g8', name: 'Pack grupal 8', price: 1519, credits: 8, days: 30, type: 'grupal' },
  g12: { id: 'g12', name: 'Pack grupal 12', price: 1999, credits: 12, days: 30, type: 'grupal' },
  gm: { id: 'gm', name: 'Mensualidad grupal', price: 2800, credits: 999, days: 30, type: 'grupal' },
};

function getPlan(planId) {
  return PLANS[planId] || null;
}

module.exports = { PLANS, getPlan };
