// Probe harness: one fresh browser context per probe, a saved API key, and a fake
// Anthropic endpoint whose answer is set per probe via h.plan = (note, records) => plan.
const { chromium } = require('playwright');
const FILE = 'file://' + require('path').join(__dirname, '..', 'build', 'Ace-demo.html');
const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type,x-api-key,anthropic-version,anthropic-dangerous-direct-browser-access', 'access-control-allow-methods': 'POST, OPTIONS' };
const A = o => Object.assign({ type: '', ref: '', customerName: '', phone: '', address: '', jobType: '', date: '', time: '', price: '', paymentType: '', paid: '', done: '', newDate: '', newTime: '', dumpsterNumber: '', otherDumpsterNumber: '', actualTons: '', agreedTons: '', dueBack: '', note: '', newName: '', newPhone: '', newAddress: '', contact: '', message: '' }, o);
const pad2 = n => String(n).padStart(2, '0'); const iso = d => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
const TODAY = iso(new Date());
const refIn = (records, re) => { const m = records.match(re); return m ? m[1] : ''; };
let browser;
async function open(opts = {}) {
  if (!browser) browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const h = { page, ctx, errors: [], requests: [], plan: () => ({ reply: '', actions: [], issues: [] }), raw: null };
  page.on('pageerror', e => h.errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/status of 401/.test(m.text())) h.errors.push('console: ' + m.text()); });
  await page.addInitScript(([state, mode]) => {
    try { if (!sessionStorage.getItem('init')) { sessionStorage.setItem('init', '1'); localStorage.setItem('ace-demo-apikey', 'sk-ant-api03-probe-0001'); if (state) localStorage.setItem('ace-demo-v1', state); if (mode) localStorage.setItem('ace-demo-v1:mode', mode); } } catch (e) {}
  }, [opts.state ? JSON.stringify(opts.state) : null, opts.mode || null]);
  await page.route('https://api.anthropic.com/**', async route => {
    const req = route.request();
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
    const key = req.headers()['x-api-key'] || '';
    if (key === 'connection-check') return route.fulfill({ status: 401, headers: { ...CORS, 'content-type': 'application/json' }, body: '{"type":"error","error":{"type":"authentication_error","message":"x"}}' });
    let note = '', records = '';
    try { const content = JSON.parse(req.postData()).messages[0].content; const m = content.match(/^Spoken note:\n([\s\S]*?)\n\nRecords:\n([\s\S]*)$/); note = m ? m[1] : content; records = m ? m[2] : ''; } catch (e) {}
    h.requests.push({ note, records, body: req.postData() });
    const plan = h.plan(note, records);
    const text = typeof plan === 'string' ? plan : JSON.stringify(plan);
    return route.fulfill({ status: 200, headers: { ...CORS, 'content-type': 'application/json' }, body: JSON.stringify({ stop_reason: 'end_turn', content: [{ type: 'text', text }] }) });
  });
  await page.goto(FILE); await page.waitForTimeout(300);
  h.root = () => (h.isMac ? '#mac' : '#overlay');
  h.isMac = opts.mode === 'mac';
  h.ov = async () => ((await page.locator(h.isMac ? '#mac .sheet' : '#overlay').first().textContent().catch(() => '')) || '').replace(/\s+/g, ' ');
  h.dialog = async () => ((await page.locator((h.isMac ? '#mac' : '#overlay') + ' .dialog').first().textContent().catch(() => '')) || '').replace(/\s+/g, ' ');
  h.hasDialog = async () => (await page.locator((h.isMac ? '#mac' : '#overlay') + ' .dialog').count()) > 0;
  h.toast = async () => ((await page.locator('.toast').first().textContent().catch(() => '')) || '');
  h.state = async () => page.evaluate(() => JSON.parse(localStorage.getItem('ace-demo-v1')));
  h.say = async (note, wait = 500) => {
    const btn = h.isMac ? '#mac .titlebar [data-action="assistant"]' : '#nav [data-action="assistant"]';
    await page.click(btn); await page.waitForTimeout(80);
    await page.fill(`${h.isMac ? '#mac' : '#overlay'} textarea[data-field="note"]`, note);
    await page.click(`${h.isMac ? '#mac' : '#overlay'} [data-action="assistant-fill"]`); await page.waitForTimeout(wait);
  };
  h.click = async sel => { await page.click(`${h.isMac ? '#mac' : '#overlay'} ${sel}`); await page.waitForTimeout(150); };
  h.yesAll = async () => { for (let i = 0; i < 8 && (await h.hasDialog()); i++) { await page.click(`${h.isMac ? '#mac' : '#overlay'} .dialog button.bold`); await page.waitForTimeout(350); } };
  h.close = async () => { await ctx.close(); };
  return h;
}
async function done() { if (browser) await browser.close(); }
module.exports = { open, done, A, TODAY, iso, refIn };
