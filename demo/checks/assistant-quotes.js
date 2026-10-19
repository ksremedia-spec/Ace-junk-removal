const { open, done, A, refIn } = require('./harness');
const OUT = require('path').join(__dirname, 'shots') + '/';
let fails = 0; const check = (n, c, x) => { console.log((c ? 'ok   ' : 'FAIL ') + n + (c || x === undefined ? '' : '  [' + String(x).slice(0, 220) + ']')); if (!c) fails++; };
const pad = n => String(n).padStart(2, '0'); const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const plus = n => { const d = new Date(); d.setDate(d.getDate() + n); return iso(d); };
(async () => {
  const h = await open(); const p = h.page; const ov = async () => (await h.ov());
  const content = async () => ((await p.locator('#content').textContent()) || '').replace(/\s+/g, ' ');
  // Today line
  let c = await content();
  check('Today shows Quotes to follow up: 2', /Quotes to follow up\s*2/.test(c), c.slice(0, 260));
  await p.click('#content [data-action="today-quotes"]'); await p.waitForTimeout(120);
  check('tapping it opens Quotes on Open', /4 open/.test(await content()) && /Follow up/.test(await content()));
  // Records carry open quotes
  h.plan = (note, records) => ({ reply: 'ok', actions: [], issues: [] });
  await h.say('which quotes need a call back', 700);
  const rec = h.requests[h.requests.length - 1].records;
  check('records list the open quotes with Q references', /Open quotes:\n- Q1 C\d+ Dave Macomber/.test(rec) && /\(overdue\)/.test(rec) && /\(today\)/.test(rec) && !/kitchen redo/.test(rec), rec.split('Open quotes:')[1] && rec.split('Open quotes:')[1].slice(0, 300));
  await p.click('#overlay [data-action="close-sheet"]'); await p.waitForTimeout(100);
  // new_quote for someone not in the records
  h.plan = () => ({ reply: '', actions: [A({ type: 'new_quote', customerName: 'Samuel Rivera-Okafor', phone: '', address: '66 Johnson St, Taunton, MA', jobType: 'Junk removal', price: '800', note: 'Garage cleanout' })], issues: [] });
  await h.say('quote for 66 Johnson Street, garage cleanout, 800, Sam Rivera 508 555 0610', 800);
  let o = await ov();
  check('new_quote shows the New Quote screen filled in', /New Quote/.test(o) && (await p.inputValue('#overlay [data-field="g-name"]')) === 'Samuel Rivera-Okafor' && (await p.inputValue('#overlay [data-field="g-price"]')) === '800' && /Saving adds this customer/.test(o), o.slice(0, 260));
  await p.click('#overlay [data-action="assistant-g-save"]'); await p.waitForTimeout(250);
  let st = await h.state(); const sam = st.customers.find(x => x.name === 'Samuel Rivera-Okafor'); const nq = sam && st.quotes.find(q => q.customerId === sam.id);
  check('saving adds the customer and an open quote, call back in three days', !!sam && !!nq && nq.status === 'open' && nq.price === 800 && nq.followUp === plus(3) && (await h.toast()).includes('Quote saved.'));
  // Kyle's sentence: approved by address
  h.plan = () => ({ reply: '', actions: [A({ type: 'update_quote', address: '66 Johnson St', price: '800', quoteStatus: 'Approved' })], issues: [] });
  await h.say('The quote for 66 Johnson Street, 800, customer approved', 800);
  o = await ov();
  check('approved finds the quote by address and shows Book Job', /Book Job/.test(o) && /Samuel Rivera-Okafor/.test(o) && /No day was said for the work/.test(o), o.slice(0, 300));
  await p.fill('#overlay [data-field="g-date"]', plus(4)); await p.dispatchEvent('#overlay [data-field="g-date"]', 'change'); await p.waitForTimeout(80);
  await p.click('#overlay [data-action="assistant-g-save"]'); await p.waitForTimeout(250);
  st = await h.state(); const bq = st.quotes.find(q => q.id === nq.id); const bj = st.jobs.find(x => x.id === bq.jobId);
  check('Book Job adds the job on that day and marks the quote booked', bq.status === 'booked' && !!bj && bj.customerId === sam.id && bj.date === plus(4) && bj.price === 800 && bj.notes === 'Garage cleanout' && (await h.toast()).includes('Job saved.'));
  // declined by name
  h.plan = () => ({ reply: '', actions: [A({ type: 'update_quote', customerName: 'Angela Ruiz', quoteStatus: 'declined' })], issues: [] });
  await h.say('Ruiz went with someone else', 800);
  o = await ov(); check('declined shows Mark Lost', /Mark Lost/.test(o) && /Angela Ruiz/.test(o), o.slice(0, 200));
  await p.click('#overlay [data-action="assistant-g-save"]'); await p.waitForTimeout(250);
  st = await h.state(); check('the quote is lost', st.quotes.find(q => q.id === 'q3').status === 'lost' && (await h.toast()).includes('Quote marked lost.'));
  // call-back day by reference
  h.plan = (note, records) => ({ reply: '', actions: [A({ type: 'update_quote', ref: refIn(records, /- (Q\d+) [^\n]*Harborview/), followUp: plus(5) })], issues: [] });
  await h.say('call Harborview back about the quote on Saturday', 800);
  o = await ov(); check('a new call-back day shows Update Quote with the date', /Update Quote/.test(o) && (await p.inputValue('#overlay [data-field="g-followUp"]')) === plus(5));
  await p.click('#overlay [data-action="assistant-g-save"]'); await p.waitForTimeout(250);
  st = await h.state(); check('the call-back day is saved', st.quotes.find(q => q.id === 'q2').followUp === plus(5));
  await p.click('[data-action="tab"][data-tab="today"]'); await p.waitForTimeout(100);
  check('Today now shows 1 to follow up', /Quotes to follow up\s*1/.test(await content()));
  await p.screenshot({ path: OUT + 'demo-today-quotes.png', clip: await p.locator('#phone').boundingBox() });
  // a quote nobody has
  h.plan = () => ({ reply: '', actions: [A({ type: 'update_quote', customerName: 'Nobody Atall', quoteStatus: 'approved' })], issues: [] });
  await h.say('Nobody Atall approved', 800);
  check('no matching quote says so', /No open quote was found for Nobody Atall/.test(await ov()));
  check('no page errors', !h.errors.length, h.errors.join(' | '));
  await h.close();
  { const m = await open({ mode: 'mac' }); const mp = m.page;
    await mp.click('#mac [data-action="mac-section"][data-section="today"]'); await mp.waitForTimeout(120);
    const t = ((await mp.locator('#mac-list').textContent()) || '').replace(/\s+/g, ' ');
    check('Mac Today figures line ends with quotes to follow up', /2 quotes to follow up/.test(t), t.slice(0, 200));
    check('no page errors (Mac)', !m.errors.length, m.errors.join(' | ')); await m.close(); }
  await done();
  console.log(fails ? fails + ' FAILED' : 'ALL ASSISTANT QUOTE CHECKS OK');
})();
