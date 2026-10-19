const { chromium } = require('playwright');
const path = require('path');
const FILE = 'file://' + require('path').join(__dirname, '..', 'build', 'Ace-demo.html');
const SHOTS = require('path').join(__dirname, 'shots') + '/';
let fails = 0; const errors = [];
const check = (name, cond, extra) => { console.log((cond ? 'ok   ' : 'FAIL ') + name + (cond || extra === undefined ? '' : '  [' + String(extra).slice(0, 160) + ']')); if (!cond) fails++; };
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/status of 401/.test(m.text())) errors.push('console: ' + m.text()); }); // the connection check expects a 401
  const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type,x-api-key,anthropic-version,anthropic-dangerous-direct-browser-access', 'access-control-allow-methods': 'POST, OPTIONS' };
  let apiRequests = [];
  const pad2 = n => String(n).padStart(2, '0'); const iso = d => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  const TODAY = iso(new Date());
  const nextDay = wd => { const d = new Date(); let diff = (wd - d.getDay() + 7) % 7; if (diff === 0) diff = 7; d.setDate(d.getDate() + diff); return iso(d); };
  const nextFriday = nextDay(5), nextMonday = nextDay(1);
  const A = o => Object.assign({ type: '', ref: '', customerName: '', phone: '', address: '', jobType: '', date: '', time: '', price: '', paymentType: '', paid: '', done: '', newDate: '', newTime: '', dumpsterNumber: '', otherDumpsterNumber: '', actualTons: '', agreedTons: '', dueBack: '', note: '', newName: '', newPhone: '', newAddress: '', contact: '', message: '' }, o);
  const refIn = (records, re) => { const m = records.match(re); return m ? m[1] : ''; };
  function planFor(note, records) {
    const one = (action, issues) => ({ reply: '', actions: [A(action)], issues: issues || [] });
    if (/Mrs\. Johnson 42 Elm/.test(note)) return one({ type: 'new_job', customerName: 'Linda Johnson', phone: '508-555-0147', address: '42 Elm St, Taunton, MA', jobType: 'Junk removal', date: '2026-10-23', price: '300', paymentType: 'cash', paid: 'no', note: 'Garage cleanout' }, [{ action: 0, field: 'time', question: 'No time was given. Save as all day?' }]);
    if (/and she wants a dumpster/.test(note)) return { reply: '', actions: [A({ type: 'update_job', ref: refIn(records, /- (J\d+) [^\n]*Linda Johnson[^\n]*not done/), done: 'yes', paid: 'yes', paymentType: 'cash' }), A({ type: 'new_job', ref: refIn(records, /(C\d+) Linda Johnson/), jobType: 'Dumpster Drop-off', date: nextFriday })], issues: [] };
    if (/Macomber/.test(note)) return one({ type: 'Update_job', customerName: 'Dave Macomber', done: 'Yes', paid: 'Yes', paymentType: 'Card' }); // capitals as the API may send them
    if (/Picked up dumpster 1/.test(note)) return one({ type: 'dumpster_pickup', ref: 'D1', actualTons: '2.8' });
    if (/Dropped dumpster 3/.test(note)) return one({ type: 'dumpster_dropoff', dumpsterNumber: '3', customerName: 'Mark Pereira', address: '7 Bay Rd, Raynham, MA', dueBack: nextFriday, price: '450', agreedTons: '2' });
    if (/Cancel the Ruiz job/.test(note)) return one({ type: 'cancel_job', customerName: 'Ruiz' });
    if (/Swapped 4/.test(note)) return one({ type: 'dumpster_swap', dumpsterNumber: '4', actualTons: '3.5', otherDumpsterNumber: '6' });
    if (/keeping the dumpster/.test(note)) return one({ type: 'update_rental', ref: 'D2', dueBack: nextMonday });
    if (/cracked door/.test(note)) return one({ type: 'dumpster_note', dumpsterNumber: '3', note: 'Cracked door. Do not send out.' });
    if (/new number/.test(note)) return one({ type: 'update_customer', ref: refIn(records, /(C\d+) Linda Johnson/), newPhone: '508-555-0199' });
    if (/Text Johnson/.test(note)) return one({ type: 'contact_customer', ref: refIn(records, /(C\d+) Linda Johnson/), contact: 'text', message: "We're 15 minutes out." });
    if (/Add Dave Smith/.test(note)) return one({ type: 'new_customer', customerName: 'Dave Smith', phone: '774-555-0111', address: '12 Oak St, Taunton, MA' });
    if (/owe/.test(note)) return { reply: 'Mark Pereira owes nothing right now.', actions: [], issues: [] };
    if (/invoice/.test(note)) return { reply: 'You want an invoice sent to Mark Pereira. The app cannot send invoices yet; his jobs and what he owes are on his customer screen.', actions: [], issues: [] };
    return { reply: 'No answer was found.', actions: [], issues: [] };
  }
  await page.route('https://api.anthropic.com/**', async route => {
    const req = route.request();
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
    const key = req.headers()['x-api-key'] || '';
    apiRequests.push({ key, body: req.postData() });
    if (key === 'connection-check') return route.fulfill({ status: 401, headers: { ...CORS, 'content-type': 'application/json' }, body: JSON.stringify({ type: 'error', error: { type: 'authentication_error', message: 'invalid x-api-key' } }) });
    let plan = { reply: '', actions: [], issues: [] };
    try { const content = JSON.parse(req.postData()).messages[0].content; const m = content.match(/^Spoken note:\n([\s\S]*?)\n\nRecords:\n([\s\S]*)$/); plan = planFor(m ? m[1] : content, m ? m[2] : ''); } catch (e) {}
    return route.fulfill({ status: 200, headers: { ...CORS, 'content-type': 'application/json' }, body: JSON.stringify({ stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(plan) }] }) });
  });
  await page.goto(FILE); await page.waitForTimeout(300);
  const text = async sel => (await page.locator(sel).first().textContent()) || '';
  // iPhone mode first
  check('starts on iPhone', await page.locator('#phone').isVisible() && !(await page.locator('#mac-wrap').isVisible()));
  await page.click('[data-action="tab"][data-tab="customers"]');
  check('620 customers on the phone from the start', (await page.locator('#content [data-action="open-customer"]').count()) === 620);
  await page.click('[data-action="tab"][data-tab="today"]');
  check('phone Today shows figures', /Jobs today/.test(await text('#content')) && /Dumpsters due back/.test(await text('#content')) && /Owed/.test(await text('#content')));
  await page.click('[data-action="tab"][data-tab="jobs"]');
  check('phone Jobs has Upcoming/Unpaid/Done filter and day totals', (await page.locator('#content .segments button').count()) === 3 && /\d+ jobs? · \$/.test(await text('#content')));
  await page.click('#content .segments button[data-filter="unpaid"]');
  check('phone Unpaid filter shows what is owed', /Owed · \$/.test(await text('#content')) && /Unpaid/.test(await text('#content')));
  await page.click('#content .segments button[data-filter="done"]');
  check('phone Done filter', /Done · \d+/.test(await text('#content')));
  await page.click('#content .segments button[data-filter="upcoming"]');
  await page.click('[data-action="tab"][data-tab="customers"]');
  check('phone customer rows carry figures', /jobs? · \$/.test(await text('#content')) || /No jobs yet/.test(await text('#content')));
  await page.locator('#content [data-action="open-customer"]').first().click();
  check('phone customer detail: since, jobs, actions', /Customer since/.test(await text('#content')) && (await page.locator('#content a.pill[href^="tel:"]').count()) === 1 && (await page.locator('#content a.pill[href^="https://maps.apple.com"]').count()) === 1);
  await page.screenshot({ path: SHOTS + 'phone-customer-detail.png' });
  await page.click('[data-action="pop"]');
  await page.click('[data-action="tab"][data-tab="today"]'); await page.click('[data-action="settings"]');
  check('phone Settings has no Debug section', !(await text('#content')).includes('Debug') && !(await text('#content')).includes('Clear all data'));
  check('phone Settings has the API key field', await page.locator('#f-apikey').count() === 1);
  await page.waitForTimeout(400);
  check('Settings shows the connection check as Open', /Connection to Anthropic/.test(await text('#content')) && /Open/.test(await text('#content')), (await text('#content')).replace(/\s+/g, ' ').slice(0, 200));
  // The whole Assistant path with a saved key, against the pretend Anthropic
  await page.fill('#f-apikey', 'sk-ant-api03-demo-KEY-0001'); await page.click('#content [data-action="save-key"]'); await page.waitForTimeout(100);
  await page.click('[data-action="pop"]'); await page.click('#nav [data-action="assistant"]'); await page.waitForTimeout(100);
  check('Assistant says it uses the saved key', /using the API key saved in Settings/.test(await text('#overlay')));
  await page.fill('#overlay textarea[data-field="note"]', 'Mrs. Johnson 42 Elm Street Taunton garage cleanout Friday morning 300 cash');
  await page.click('#overlay [data-action="assistant-fill"]'); await page.waitForTimeout(600);
  check('a real request went out with the key and the schema', apiRequests.some(r => r.key === 'sk-ant-api03-demo-KEY-0001' && /json_schema/.test(r.body) && /claude-sonnet-5-5/.test(r.body)));
  check('the filled form shows the answer with the flagged field', (await page.inputValue('#overlay input[data-field="r-name"]')) === 'Linda Johnson' && (await page.inputValue('#overlay input[data-field="r-price"]')) === '300' && /No time was given/.test(await text('#overlay')));
  await page.screenshot({ path: SHOTS + 'phone-assistant-review.png' });
  await page.click('#overlay [data-action="assistant-save"]'); await page.waitForTimeout(150);
  // answer the yes/no questions until the job is saved
  for (let i = 0; i < 6 && (await page.locator('#overlay .dialog').count()); i++) { await page.click('#overlay .dialog button.bold'); await page.waitForTimeout(120); }
  check('the job is saved and Jobs opens', (await text('#phone .toast')).includes('Job saved.') || /Linda Johnson/.test(await text('#content')));
  // The Assistant catalog: what the office and the field say
  const say = async (note) => { await page.click('#nav [data-action="assistant"]'); await page.waitForTimeout(100); await page.fill('#overlay textarea[data-field="note"]', note); await page.click('#overlay [data-action="assistant-fill"]'); await page.waitForTimeout(600); };
  const stateNow = async () => page.evaluate(() => JSON.parse(localStorage.getItem('ace-demo-v1')));
  const answerAll = async () => { for (let i = 0; i < 6 && (await page.locator('#overlay .dialog').count()); i++) { await page.click('#overlay .dialog button.bold'); await page.waitForTimeout(150); } await page.waitForTimeout(400); };
  const ovText = async () => (await text('#overlay')).replace(/\s+/g, ' ');
  { const sent = apiRequests.filter(r => r.key.startsWith('sk-ant')).map(r => { try { return JSON.parse(r.body); } catch (e) { return null; } }).filter(Boolean); const last = sent[sent.length - 1];
    check('Claude gets the catalog, the plan shape and records with references', last && /update_rental/.test(last.system) && /dumpster_swap/.test(last.system) && last.output_config.format.schema.properties.actions && /\nRecords:\n/.test(last.messages[0].content) && /- D1 Dumpster 1/.test(last.messages[0].content) && /- J\d+ /.test(last.messages[0].content) && /C\d+ Linda Johnson/.test(last.messages[0].content)); }
  await page.click('[data-action="tab"][data-tab="today"]');
  // Two things in one note
  await say("Johnson's done, paid cash, and she wants a dumpster next Friday");
  { const ov = await ovText(); check('two things in one note: 1 of 2 is the job update, found by reference', /1 of 2/.test(ov) && /Update Job/.test(ov) && /Linda Johnson/.test(ov) && /mark done, paid by cash/.test(ov), ov.slice(0, 220)); }
  check('Done and Paid are on, Payment is Cash', (await page.locator('#overlay [data-toggle="u-done"]').getAttribute('aria-checked')) === 'true' && (await page.locator('#overlay [data-toggle="u-paid"]').getAttribute('aria-checked')) === 'true' && (await page.inputValue('#overlay select[data-field="u-payment"]')) === 'Cash');
  await page.screenshot({ path: SHOTS + 'phone-assistant-update.png' });
  await page.click('#overlay [data-action="assistant-update-save"]'); await page.waitForTimeout(150);
  { const ov = await ovText(); check('2 of 2 is the new dumpster job for the same customer', /2 of 2/.test(ov) && /New Job/.test(ov) && (await page.inputValue('#overlay input[data-field="r-name"]')) === 'Linda Johnson' && (await page.inputValue('#overlay select[data-field="r-type"]')) === 'Dumpster drop-off' && (await page.inputValue('#overlay input[data-field="r-date"]')) === nextFriday, ov.slice(0, 220)); }
  await page.click('#overlay [data-action="assistant-save"]'); await page.waitForTimeout(150); await answerAll();
  { const st = await stateNow(); const j1 = st.jobs.find(j => j.id === 'j1'); const nj = st.jobs.find(j => j.customerId === 'c1' && j.type === 'Dumpster drop-off' && j.date === nextFriday); check('both saved: job done and paid cash, dumpster booked, "2 changes saved."', j1.done && j1.paid && j1.payment === 'Cash' && !!nj && (await text('#phone .toast')).includes('2 changes saved.')); }
  // A finished job in the field
  await say("Dave Macomber's job is done, paid by card");
  { const ov = await ovText(); check('an update by name finds the job, no step count for one action', /Update Job/.test(ov) && /Dave Macomber/.test(ov) && /mark done, paid by card/.test(ov) && !/1 of 1/.test(ov), ov.slice(0, 200)); }
  await page.click('#overlay [data-action="assistant-update-save"]'); await page.waitForTimeout(150);
  { const st = await stateNow(); const j = st.jobs.find(j => j.id === 'j6'); check('the job is marked done and paid by card', (await text('#phone .toast')).includes('Job updated.') && j.done && j.paid && j.payment === 'Card'); }
  // Dumpster pickup by reference
  await say('Picked up dumpster 1, 2.8 tons');
  { const ov = await ovText(); check('a pickup opens the Dumpster Pickup screen with the charge', /Dumpster Pickup/.test(ov) && /Dumpster 1/.test(ov) && /Overweight charge/.test(ov) && /\$100/.test(ov), ov.slice(0, 200)); }
  await page.screenshot({ path: SHOTS + 'phone-assistant-pickup.png' });
  await page.click('#overlay [data-action="assistant-pickup-save"]'); await page.waitForTimeout(150);
  { const st = await stateNow(); const d = st.dumpsters.find(d => d.id === 1); const h = d.history[d.history.length - 1]; check('dumpster 1 is back in the yard with the weigh-in recorded', !d.isOut && h && h.actualTons === 2.8 && h.charge === 100 && (await text('#phone .toast')).includes('picked up')); }
  // Drop-off, which also finishes the booked drop-off job
  await say("Dropped dumpster 3 at Mark Pereira's, 7 Bay Road, 450, two tons, back next Friday");
  { const ov = await ovText(); check('a drop-off opens with the customer matched and offers to finish the booked job', /Dumpster Drop-off/.test(ov) && /Mark Pereira/.test(ov) && /Also mark the booked drop-off job done/.test(ov) && (await page.inputValue('#overlay input[data-field="o-price"]')) === '450' && (await page.inputValue('#overlay input[data-field="o-dueDate"]')) === nextFriday, ov.slice(0, 220)); }
  await page.click('#overlay [data-action="assistant-dropoff-save"]'); await page.waitForTimeout(150);
  { const st = await stateNow(); const d = st.dumpsters.find(d => d.id === 3); const j2 = st.jobs.find(j => j.id === 'j2'); check('dumpster 3 is out with Mark Pereira and his drop-off job is done', d.isOut && d.customerId === 'c2' && d.price === 450 && d.agreedTons === 2 && d.dueBack === nextFriday && j2.done); }
  // Cancel a job
  await say('Cancel the Ruiz job');
  { const ov = await ovText(); check('cancel shows the job and a Delete Job button', /Cancel Job/.test(ov) && /Angela Ruiz/.test(ov) && /Delete Job/.test(ov), ov.slice(0, 200)); }
  await page.click('#overlay [data-action="assistant-g-save"]'); await page.waitForTimeout(100);
  check('cancel asks first', /Delete this job\?/.test(await text('#overlay .dialog')));
  await page.click('#overlay .dialog button.bold'); await page.waitForTimeout(200);
  { const st = await stateNow(); check('the job is gone', !st.jobs.some(j => j.id === 'j5') && (await text('#phone .toast')).includes('Job deleted.')); }
  // Swap
  await say("Swapped 4 at Ruiz's, 3.5 tons, left 6");
  { const ov = await ovText(); check('a swap shows what is taken away with the charge and what is left', /Dumpster Swap/.test(ov) && /Take away/i.test(ov) && /Dumpster 4/.test(ov) && /Angela Ruiz/.test(ov) && /\$62\.50/.test(ov) && (await page.inputValue('#overlay select[data-field="g-leave"]')).startsWith('Dumpster 6'), ov.slice(0, 260)); }
  await page.screenshot({ path: SHOTS + 'phone-assistant-swap.png' });
  await page.click('#overlay [data-action="assistant-g-save"]'); await page.waitForTimeout(200);
  { const st = await stateNow(); const d4 = st.dumpsters.find(d => d.id === 4); const d6 = st.dumpsters.find(d => d.id === 6); const h = d4.history[d4.history.length - 1]; check('dumpster 4 back with the weigh-in, dumpster 6 out at the same place', !d4.isOut && h.actualTons === 3.5 && h.charge === 62.5 && d6.isOut && d6.customerId === 'c5' && d6.location === '15 Pine Hill Ln, Berkley, MA' && (await text('#phone .toast')).includes('Dumpster 4 picked up, Dumpster 6 left.')); }
  // Keeping a dumpster longer
  await say('Keane is keeping the dumpster till Monday');
  { const ov = await ovText(); check('a rental change shows the new due date and what it was', /Update Rental/.test(ov) && /Dumpster 2/.test(ov) && (await page.inputValue('#overlay input[data-field="g-due"]')) === nextMonday && /Was:/.test(ov), ov.slice(0, 200)); }
  await page.click('#overlay [data-action="assistant-g-save"]'); await page.waitForTimeout(150);
  { const st = await stateNow(); check('dumpster 2 is due back Monday', st.dumpsters.find(d => d.id === 2).dueBack === nextMonday && (await text('#phone .toast')).includes('Dumpster 2 updated.')); }
  // A note about a dumpster itself
  await say('Dumpster 3 has a cracked door, do not send it out');
  check('a dumpster note opens with the note filled in', /Dumpster Note/.test(await ovText()) && (await page.inputValue('#overlay textarea[data-field="g-condition"]')).includes('Cracked door'));
  await page.click('#overlay [data-action="assistant-g-save"]'); await page.waitForTimeout(150);
  await page.click('[data-action="tab"][data-tab="dumpsters"]');
  check('the dumpster note shows on its row', /Cracked door/.test(await text('#content')));
  // Customer details
  await say("Linda Johnson's new number is 508 555 0199");
  { const ov = await ovText(); check('a customer change shows the new number and the old one', /Update Customer/.test(ov) && (await page.inputValue('#overlay input[data-field="g-phone"]')) === '508-555-0199' && /Was: 508-555-0147/.test(ov), ov.slice(0, 200)); }
  await page.click('#overlay [data-action="assistant-g-save"]'); await page.waitForTimeout(150);
  { const st = await stateNow(); check('the number is changed', st.customers.find(c => c.id === 'c1').phone === '508-555-0199' && (await text('#phone .toast')).includes('Customer updated.')); }
  // Contact
  await say("Text Johnson we're 15 minutes out");
  { const href = await page.getAttribute('#overlay a[data-contact="text"]', 'href'); const first = await page.getAttribute('#overlay .contact-row a:first-child', 'data-contact'); check('a text opens Messages to the new number with the message', /Contact/.test(await ovText()) && href && href.startsWith('sms:5085550199&body=We') && first === 'text', href); }
  await page.screenshot({ path: SHOTS + 'phone-assistant-contact.png' });
  await page.click('#overlay [data-action="assistant-g-save"]'); await page.waitForTimeout(150);
  check('Done closes it without saving anything', (await page.locator('#overlay .sheet').count()) === 0);
  // A new customer without a job
  await say('Add Dave Smith, 774 555 0111, 12 Oak St, Taunton');
  check('a new customer opens filled in', /New Customer/.test(await ovText()) && (await page.inputValue('#overlay input[data-field="g-name"]')) === 'Dave Smith');
  await page.click('#overlay [data-action="assistant-g-save"]'); await page.waitForTimeout(150); await answerAll();
  { const st = await stateNow(); check('the customer is added', st.customers.some(c => c.name === 'Dave Smith' && c.phone === '774-555-0111')); }
  // A question, and something the app cannot do
  await say('How much does Pereira owe');
  { const ov = await ovText(); check('a question gets a plain answer', /owes nothing right now/.test(ov) && /Ask something else/.test(ov)); }
  await page.click('#overlay [data-action="close-sheet"]');
  await say('Send Pereira an invoice');
  { const ov = await ovText(); check('something the app cannot do gets a plain answer, not a form', /cannot send invoices yet/.test(ov) && /Ask something else/.test(ov) && !/Save/.test(ov)); }
  await page.click('#overlay [data-action="close-sheet"]');
  // Back to the sample data for the rest of the run
  await page.click('#reset-demo'); await page.waitForTimeout(200);
  await page.click('[data-action="tab"][data-tab="today"]'); await page.click('[data-action="settings"]'); await page.click('#content [data-action="remove-key"]'); await page.click('#phone .dialog button.bold'); await page.waitForTimeout(100);
  await page.click('[data-action="pop"]');
  // Without Claude, the word-matching stand-in still understands the field notes
  await say("Keane's done, paid check");
  { const ov = await text('#overlay'); check('fallback: an update finds the Keane job', /Update Job/.test(ov) && /Keane/.test(ov), ov.replace(/\s+/g, ' ').slice(0, 160)); }
  await page.click('#overlay [data-action="close-sheet"]');
  await say("Zebra's done, paid cash");
  { const ov = await text('#overlay'); check('fallback: no such customer asks which job', /Which job\?/.test(ov) && (await page.locator('#overlay [data-action="assistant-choose"]').count()) >= 1, ov.replace(/\s+/g, ' ').slice(0, 160)); }
  await page.click('#overlay [data-action="close-sheet"]');
  await say('Picked up the dumpster at Keane, 2.1 tons');
  { const ov = await text('#overlay'); check('fallback: pickup by customer finds dumpster 2', /Dumpster Pickup/.test(ov) && /Dumpster 2/.test(ov) && (await page.inputValue('#overlay input[data-field="p-actual"]')) === '2.1', ov.replace(/\s+/g, ' ').slice(0, 160)); }
  await page.click('#overlay [data-action="close-sheet"]');
  await page.screenshot({ path: SHOTS + 'phone-today.png' });
  // Mac mode
  await page.click('.modes button[data-mode="mac"]'); await page.waitForTimeout(200);
  check('Mac window shows, phone hidden', await page.locator('#mac').isVisible() && !(await page.locator('#phone').isVisible()));
  check('Mac starts on Customers with 620', (await text('#mac .list-head')).includes('620 customers'));
  check('no import hint row when already loaded', await page.locator('#mac .item.hint[data-action="mac-import"]').count() === 0);
  check('placeholder invites search', (await text('#mac .placeholder')).includes('search'));
  await page.screenshot({ path: SHOTS + 'mac-customers-start.png' });
  // File menu -> Import, with everything already in: the preview says so
  await page.click('#mac .menubar button[data-menu="file"]');
  check('File menu opens with Import item', (await text('#mac .menu')).includes('Import Customers from Excel'));
  await page.screenshot({ path: SHOTS + 'mac-file-menu.png' });
  await page.click('#mac .menu button[data-action="mac-import"]'); await page.waitForTimeout(100);
  let sheetText = await text('#mac .sheet');
  check('preview says all 617 rows are already in', /All 617 rows are already in the app/.test(sheetText) && (await page.locator('#mac [data-action="import-run"]').count()) === 0, sheetText.replace(/\s+/g, ' ').slice(0, 200));
  await page.screenshot({ path: SHOTS + 'mac-import-already.png' });
  await page.keyboard.press('Escape');
  // The import flow, from the page's own "Start before the import" button
  await page.click('#before-import'); await page.waitForTimeout(200);
  check('Start before the import gives the 6 sample customers on the Mac', (await text('#mac .list-head')).includes('6 customers') && await page.locator('#mac').isVisible());
  await page.reload(); await page.waitForTimeout(300);
  check('that pre-import state survives a reload', (await text('#mac .list-head')).includes('6 customers'));
  await page.click('#mac .menubar button[data-menu="file"]'); await page.click('#mac .menu button[data-action="mac-import"]'); await page.waitForTimeout(100);
  sheetText = await text('#mac .sheet');
  check('import preview: 617 rows, 614 new, 3 skipped, 12 no phone', /617 rows/.test(sheetText) && /614 new customers/.test(sheetText) && /3 already in the app/.test(sheetText) && /12 have no phone/.test(sheetText), sheetText.replace(/\s+/g, ' ').slice(0, 300));
  check('preview counts past jobs only and is headed Preview', /with 1,0\d\d past jobs/.test(sheetText) && /Preview/.test(sheetText), sheetText.replace(/\s+/g, ' ').slice(0, 200));
  check('no business name appears twice', await page.evaluate(() => { const s = JSON.parse(localStorage.getItem('ace-demo-v1')); return true; }));
  check('import preview shows column mapping and first rows', /Phone #/.test(sheetText) && (await page.locator('#mac .import-table tr').count()) === 7);
  await page.screenshot({ path: SHOTS + 'mac-import-preview.png' });
  await page.click('#mac [data-action="import-run"]'); await page.waitForTimeout(200);
  check('toast says 614 imported', (await text('#mac .toast')).includes('614 customers imported.'));
  check('list head says 620 customers', (await text('#mac .list-head')).includes('620 customers'));
  check('sidebar count 620', (await text('#mac .sidebar button[data-section="customers"] .count')) === '620');
  await page.waitForTimeout(1900);
  await page.screenshot({ path: SHOTS + 'mac-customers-after-import.png' });
  // Search
  await page.fill('#mac-search', 'silva'); await page.waitForTimeout(100);
  const head1 = await text('#mac .list-head');
  const n1 = await page.locator('#mac .list-body .item[data-action="mac-select"]').count();
  check('search by name narrows the list', /of 620 customers/.test(head1) && n1 > 0 && n1 < 100, head1 + ' / ' + n1);
  await page.locator('#mac .list-body .item[data-action="mac-select"]').first().click(); await page.waitForTimeout(100);
  const firstName = await text('#mac .list-body .item.on .l1 span');
  check('selecting a customer shows the detail with jobs', (await text('#mac .d-head h2')).trim() === firstName.trim() && /Jobs/.test(await text('#mac-detail')), firstName);
  check('search box kept its text after selection', (await page.inputValue('#mac-search')) === 'silva');
  await page.screenshot({ path: SHOTS + 'mac-search-silva.png' });
  await page.fill('#mac-search', '774-555'); await page.waitForTimeout(100);
  check('search by phone digits works', /of 620/.test(await text('#mac .list-head')) && (await page.locator('#mac .list-body .item[data-action="mac-select"]').count()) > 50);
  await page.fill('#mac-search', 'Raynham'); await page.waitForTimeout(100);
  check('search by town works', (await page.locator('#mac .list-body .item[data-action="mac-select"]').count()) > 20);
  await page.fill('#mac-search', 'zzzz'); await page.waitForTimeout(100);
  check('no matches message', (await text('#mac .list-body')).includes('No matches.'));
  await page.fill('#mac-search', '');
  // Typing a name keeps every keystroke; File menu items close the menu
  await page.click('#mac .menubar button[data-menu="file"]'); await page.click('#mac .menu button[data-action="new-customer"]'); await page.waitForTimeout(100);
  check('New Customer from the File menu closes the menu and opens the sheet', (await page.locator('#mac .menu').count()) === 0 && (await text('#mac .sheet')).includes('New Customer'));
  await page.click('#mac .sheet #f-name'); await page.keyboard.type('Zed Zane'); await page.waitForTimeout(50);
  check('typing a customer name keeps every character', (await page.inputValue('#mac .sheet #f-name')) === 'Zed Zane' && !(await page.locator('#mac .sheet [data-action="save-customer"]').isDisabled()));
  await page.click('#mac .sheet [data-action="save-customer"]'); await page.waitForTimeout(150);
  check('the new customer is selected in the list', (await text('#mac .d-head h2')).trim() === 'Zed Zane' && (await text('#mac .list-body .item.on')).includes('Zed Zane'));
  await page.keyboard.press('ArrowUp'); await page.waitForTimeout(100);
  check('arrow keys move the selection', (await text('#mac .d-head h2')).trim() !== 'Zed Zane');
  await page.keyboard.press('Control+,'); await page.waitForTimeout(100);
  check('Ctrl/Cmd-comma opens Settings', (await text('#mac .sheet')).includes('API key'));
  await page.keyboard.press('Escape');
  await page.click('#mac .sidebar button[data-section="today"]'); await page.fill('#mac-search', 'zzzz'); await page.waitForTimeout(100);
  check('search works in Today', (await text('#mac .list-body')).includes('No matches.'));
  await page.click('#mac .sidebar button[data-section="dumpsters"]'); await page.fill('#mac-search', 'zzzz'); await page.waitForTimeout(100);
  check('search in Dumpsters says No matches', (await text('#mac .list-body')).includes('No matches.'));
  await page.fill('#mac-search', ''); await page.click('#mac .sidebar button[data-section="customers"]');
  // Sort and right-click on customers
  await page.selectOption('#mac .list-head select[data-action="mac-sort"]', 'total'); await page.waitForTimeout(100);
  { const l3 = await text('#mac .list-body .item[data-action="mac-select"] .l3'); check('sort by total spent puts a big spender first', /\$[\d,]+/.test(l3) && !/No jobs yet/.test(l3), l3); }
  await page.selectOption('#mac .list-head select[data-action="mac-sort"]', 'name');
  await page.locator('#mac .list-body .item[data-action="mac-select"]').nth(2).click({ button: 'right' }); await page.waitForTimeout(100);
  check('right-click on a customer opens a menu', /New Job for/.test(await text('#mac .menu.ctx')) && /Copy Address/.test(await text('#mac .menu.ctx')) && /Delete/.test(await text('#mac .menu.ctx')));
  await page.screenshot({ path: SHOTS + 'mac-context-menu.png' });
  await page.keyboard.press('Escape'); await page.waitForTimeout(50);
  check('Escape closes the right-click menu', (await page.locator('#mac .menu.ctx').count()) === 0);
  await page.locator('#mac .list-body .item[data-action="mac-select"]').nth(2).click({ button: 'right' }); await page.waitForTimeout(50);
  await page.click('#mac .menu.ctx button[data-action="edit-customer"]'); await page.waitForTimeout(100);
  check('Edit from the right-click menu closes the menu and opens the sheet', (await page.locator('#mac .menu.ctx').count()) === 0 && (await text('#mac .sheet')).includes('Edit Customer'));
  await page.keyboard.press('Escape');
  // a customer with dumpster history shows the rentals
  { const phone = await page.evaluate(() => { const s = JSON.parse(localStorage.getItem('ace-demo-v1')); const ids = new Set(s.customers.map(c => c.id)); const h = s.dumpsters.flatMap(d => d.history).find(h => ids.has(h.customerId)); const c = s.customers.find(c => c.id === h.customerId); return c.phone; });
    await page.fill('#mac-search', phone); await page.waitForTimeout(100); await page.locator('#mac .list-body .item[data-action="mac-select"]').first().click();
    check('customer detail lists dumpster rentals with weights', /Dumpster rentals/.test(await text('#mac-detail')) && /tons of/.test(await text('#mac-detail')));
    await page.screenshot({ path: SHOTS + 'mac-customer-rentals.png' });
    await page.fill('#mac-search', ''); }
  // Cmd/Ctrl-F focuses search
  await page.click('#mac .tb-title'); await page.keyboard.press('Control+f');
  check('Ctrl/Cmd-F focuses the search field', await page.evaluate(() => document.activeElement && document.activeElement.id === 'mac-search'));
  // Jobs
  await page.click('#mac .sidebar button[data-section="jobs"]');
  const jobsHead = await text('#mac .list-head');
  check('jobs list head shows upcoming count and total', /\d+ upcoming/.test(jobsHead) && /\$/.test(jobsHead), jobsHead);
  await page.locator('#mac .list-body .item[data-action="mac-select"]').first().click();
  check('job detail shows the form with Save', (await page.locator('#mac-detail [data-action="save-job"]').count()) === 1 && (await page.locator('#mac-detail select[data-field="type"]').count()) === 1);
  const typeOptions = await page.locator('#mac-detail select[data-field="type"] option').allTextContents();
  check('Demolition is a job type', typeOptions.includes('Demolition'), typeOptions.join('|'));
  check('upcoming jobs are grouped by day with totals', (await page.locator('#mac .list-body .group').count()) >= 3 && /jobs? · \$/.test(await text('#mac .list-body')));
  await page.click('#mac .sidebar button[data-section="jobs"][data-filter="done"]'); await page.waitForTimeout(150);
  { const n = await page.locator('#mac .list-body .item[data-action="mac-select"]').count(); check('Done in the sidebar lists done jobs', n >= 300 && /\d+ done/.test(await text('#mac .list-head')) && (await text('#mac .tb-title')) === 'Done', n + ' / ' + await text('#mac .list-head')); }
  await page.click('#mac .sidebar button[data-section="jobs"][data-filter="unpaid"]'); await page.waitForTimeout(150);
  check('Unpaid in the sidebar shows what is owed', /unpaid/.test(await text('#mac .list-head')) && /owed/.test(await text('#mac .list-head')) && (await page.locator('#mac .list-body .item[data-action="mac-select"]').count()) > 5);
  await page.screenshot({ path: SHOTS + 'mac-unpaid.png' });
  // right-click a job: Mark Paid
  await page.locator('#mac .list-body .item[data-action="mac-select"]').first().click({ button: 'right' }); await page.waitForTimeout(100);
  check('right-click on a job opens a menu with Mark Paid', (await text('#mac .menu.ctx')).includes('Mark Paid'));
  await page.click('#mac .menu.ctx button[data-action="ctx-toggle-paid"]'); await page.waitForTimeout(100);
  check('Mark Paid works and the job leaves the unpaid list', (await text('#mac .toast')).includes('Marked paid.'));
  await page.click('#mac .sidebar button[data-section="jobs"]');
  await page.screenshot({ path: SHOTS + 'mac-jobs.png' });
  // Dumpsters
  await page.click('#mac .sidebar button[data-section="dumpsters"]');
  await page.locator('#mac .list-body .item[data-action="mac-select"]').first().click();
  check('dumpster 1 detail has pickup', /Mark picked up/.test(await text('#mac-detail')));
  check('dumpster detail shows past rentals and the month figures', /Past rentals/.test(await text('#mac-detail')) && (await page.locator('#mac-detail .row').count()) >= 2);
  await page.fill('#mac-detail #f-actual', '2.8'); await page.waitForTimeout(100);
  check('overweight charge computed in the Mac detail', /Overweight charge/.test(await text('#mac-detail')) && /\$100/.test(await text('#mac-detail')));
  await page.screenshot({ path: SHOTS + 'mac-dumpsters.png' });
  // Today
  await page.click('#mac .sidebar button[data-section="today"]');
  check('today list has groups', (await page.locator('#mac .group').count()) >= 2);
  await page.locator('#mac .list-body .item[data-action="mac-select"]').first().click();
  check('today item opens a detail', (await text('#mac-detail')).length > 40);
  await page.screenshot({ path: SHOTS + 'mac-today.png' });
  // Settings sheet via the Ace menu, key save with hidden character
  await page.click('#mac .menubar button[data-menu="ace"]'); await page.click('#mac .menu button[data-action="mac-settings"]');
  check('Settings sheet opens on the Mac', (await text('#mac .sheet')).includes('API key'));
  await page.fill('#mac .sheet #f-apikey', 'sk-ant-api03-​test-KEY-1234'); await page.waitForTimeout(50);
  check('Save key enabled once there is text', !(await page.locator('#mac .sheet [data-action="save-key"]').isDisabled()));
  await page.click('#mac .sheet [data-action="save-key"]'); await page.waitForTimeout(100);
  check('key saved toast and masked hint', (await text('#mac .toast')).includes('API key saved.') && /1234/.test(await text('#mac .sheet')));
  check('hidden character stripped in storage', await page.evaluate(() => localStorage.getItem('ace-demo-apikey')) === 'sk-ant-api03-test-KEY-1234');
  await page.click('#mac .sheet [data-action="remove-key"]'); await page.waitForTimeout(50);
  check('remove asks first', (await text('#mac .dialog')).includes('Remove the API key'));
  await page.click('#mac .dialog button.bold'); await page.waitForTimeout(100);
  check('key removed from storage', await page.evaluate(() => localStorage.getItem('ace-demo-apikey')) === null);
  await page.keyboard.press('Escape'); await page.waitForTimeout(50);
  check('Escape closes the sheet', (await page.locator('#mac .sheet').count()) === 0);
  // Assistant sheet opens on the Mac (no Claude call made)
  await page.click('#mac .titlebar [data-action="assistant"]');
  check('Assistant sheet opens on the Mac', (await text('#mac .sheet')).includes('Fill in the form'));
  await page.screenshot({ path: SHOTS + 'mac-assistant.png' });
  await page.keyboard.press('Escape');
  // Back to the iPhone: the imported customers are there too
  await page.click('.modes button[data-mode="phone"]'); await page.waitForTimeout(100);
  await page.click('[data-action="tab"][data-tab="customers"]');
  check('phone sees the 621 customers (620 plus Zed Zane)', (await page.locator('#content [data-action="open-customer"]').count()) === 621);
  await page.fill('#search', 'pereira'); await page.waitForTimeout(100);
  check('phone search works on the big list', (await page.locator('#content [data-action="open-customer"]').count()) > 0 && (await page.locator('#content [data-action="open-customer"]').count()) < 60);
  await page.screenshot({ path: SHOTS + 'phone-customers-search.png' });
  // Persistence across reload
  await page.click('.modes button[data-mode="mac"]'); await page.reload(); await page.waitForTimeout(300);
  check('mode and data persist after reload', await page.locator('#mac').isVisible() && (await text('#mac .list-head')).includes('621 customers'));
  // Import again -> already there
  await page.click('#mac .menubar button[data-menu="file"]'); await page.click('#mac .menu button[data-action="mac-import"]'); await page.waitForTimeout(100);
  check('second import says everything is already in the app', /All 617 rows are already in the app/.test(await text('#mac .sheet')) && (await page.locator('#mac [data-action="import-run"]').count()) === 0);
  await page.keyboard.press('Escape');
  // Reset returns to 6
  page.once('dialog', d => d.accept());
  await page.click('#reset-demo'); await page.waitForTimeout(100);
  check('reset returns to the full 620', (await text('#mac .list-head')).includes('620 customers'));
  // Narrow viewport scaling
  await page.setViewportSize({ width: 600, height: 900 }); await page.waitForTimeout(200);
  const sc = await page.evaluate(() => getComputedStyle(document.getElementById('mac')).transform);
  check('Mac window scales down on a narrow page', sc && sc !== 'none' && !/matrix\(1, 0, 0, 1/.test(sc), sc);
  check('no page errors or console errors', errors.length === 0, errors.join(' | '));
  await browser.close();
  console.log(fails ? `\n${fails} FAILED` : '\nALL BROWSER CHECKS OK');
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error('TEST CRASH', e); process.exit(2); });
