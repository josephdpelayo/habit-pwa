const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(require('node:path').join(__dirname, '../app.html'), 'utf8');
const source = html.slice(html.indexOf('async function renderDashboard(){'), html.indexOf('\nfunction renderDashKPIs(){'));
async function check(countResult, expected, reject = false) {
  const els = {'admin-action-center': {}, 'dash-kpis': {}};
  const queries = [];
  const ctx = {
    console: {error() {}}, renderDailyQuote() {}, mazToday: () => '2026-11-24',
    addDaysDS: () => '2026-11-10', PLANS: {individual: [], grupal: []},
    isRealMemberPayment: () => false, isAppOnlyProfile: () => false,
    MXN: String, renderRevenueChart() {}, renderBookingsChart() {}, renderPlansChart() {},
    document: {getElementById: id => els[id] || null},
    sb: {from(table) {
      const q = {table, filters: [], select(fields, opts) {this.opts = opts; return this;},
        eq(...args) {this.filters.push(args); return this;}, neq() {return this;},
        gte() {return this;}, order() {return this;}, limit() {return this;},
        then(ok, fail) {
          queries.push(this);
          // Simulate a truncated historical list with no rows for today.
          if (this.opts?.head) return (reject ? Promise.reject(new Error('offline')) : Promise.resolve(countResult)).then(ok, fail);
          return Promise.resolve({data: table === 'bookings' ? [{ds: '2026-01-01'}] : []}).then(ok, fail);
        }};
      return q;
    }}
  };
  vm.createContext(ctx);
  await vm.runInContext(source + '\nrenderDashboard()', ctx);
  assert.ok(els['admin-action-center'].innerHTML.includes('admin-action-count">' + expected + '</div>'));
  assert.ok(els['dash-kpis'].innerHTML.includes('>' + expected + '</div>'));
  const countQuery = queries.find(q => q.opts?.head);
  assert.equal(countQuery.opts.count, 'exact');
  assert.deepEqual(countQuery.filters, [['ds', '2026-11-24'], ['status', 'active']]);
}
(async () => {
  await check({count: 3}, 3);
  await check({count: 0}, 0);
  await check({count: null, error: {message: 'failed'}}, '—');
  await check({count: null}, '—');
  await check(null, '—', true);
  console.log('Admin Agenda: exact daily counts and query failures OK');
})().catch(e => {console.error(e); process.exitCode = 1;});
