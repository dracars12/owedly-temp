import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { load } from 'cheerio';

const ROOT = new URL('../../', import.meta.url);
const TEMPLATE = new URL('../../realtime-database.json', import.meta.url);
const OUTPUT = new URL('../../realtime-database.full.json', import.meta.url);
const OPEN_URL = 'https://www.classaction.org/settlements';
const UPCOMING_URL = 'https://www.classaction.org/news/category/class-action-settlement';
const USER_AGENT = 'Owedly-Snapshot/1.0 (manual catalog snapshot)';
const MAX_OPEN_PAGES = 100; // safety ceiling; normal run stops when pagination ends
const MAX_UPCOMING_PAGES = 50; // safety ceiling; normal run stops when pagination/lookback ends
const UPCOMING_LOOKBACK_DAYS = 75;
const REQUEST_DELAY_MS = 1800; // polite sequential pacing between page requests
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function collapse(v='') { return v.replace(/\s+/g, ' ').trim(); }
function abs(raw, base) { try { return new URL(raw, base).href; } catch { return null; } }
function isoDeadline(raw) {
  if (!raw || /varies/i.test(raw)) return null;
  const m = raw.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})$/);
  if (!m) return null;
  let y = Number(m[3]); if (y < 100) y += 2000;
  return new Date(Date.UTC(y, Number(m[1])-1, Number(m[2]), 23, 59, 0)).toISOString();
}
function stableId(title, stableKey='') {
  const slug = collapse(title).toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,72) || 'settlement';
  const h = crypto.createHash('sha256').update(title + '|' + stableKey).digest('hex').slice(0,8);
  return `${slug}-${h}`;
}
function companyFrom(title) {
  const t = collapse(title);
  const aliases = [
    [/youtube|\bgoogle\b/i,'Google'], [/\bamazon\b/i,'Amazon'], [/at&t/i,'AT&T'], [/tiktok/i,'TikTok'],
    [/bank of america/i,'Bank of America'], [/facebook|meta platforms|\bmeta\b/i,'Facebook']
  ];
  for (const [re,c] of aliases) if (re.test(t)) return c;
  if (t.includes(' - ')) return t.split(' - ')[0].trim();
  return t.replace(/Class Action Settlement/ig,'').replace(/Settlement$/i,'').trim();
}
function categoryFor(title, desc='') {
  const t=(title+' '+desc).toLowerCase();
  if (/data breach|cyberattack|ransomware|cyber incident/.test(t)) return 'Data Breach';
  if (/privacy|tracking pixel|biometric|personal data/.test(t)) return 'Privacy';
  if (/antitrust|price[- ]fixing|monopol/.test(t)) return 'Antitrust';
  if (/wage|overtime|employment|employee|worker|labor law|job postings/.test(t)) return 'Employment';
  if (/bank|credit union|overdraft|mortgage|securities|401\(k\)|retirement/.test(t)) return 'Banking';
  if (/vehicle|car|truck|automotive|hyundai|kia|toyota|nissan|ford|bmw|dodge|ram/.test(t)) return 'Automotive';
  if (/health|hospital|medical|patient|pharma|drug|clinic/.test(t)) return 'Healthcare';
  if (/subscription|streaming|renewal/.test(t)) return 'Subscriptions';
  if (/google|youtube|software|app|technology|mobile|data/.test(t)) return 'Technology';
  if (/retail|purchase|store|ticket|fees|discount|marketing/.test(t)) return 'Retail';
  return 'Other';
}
const STATES = ['Alabama','Alaska','Arizona','Arkansas','California','Colorado','Connecticut','Delaware','Florida','Georgia','Hawaii','Idaho','Illinois','Indiana','Iowa','Kansas','Kentucky','Louisiana','Maine','Maryland','Massachusetts','Michigan','Minnesota','Mississippi','Missouri','Montana','Nebraska','Nevada','New Hampshire','New Jersey','New Mexico','New York','North Carolina','North Dakota','Ohio','Oklahoma','Oregon','Pennsylvania','Rhode Island','South Carolina','South Dakota','Tennessee','Texas','Utah','Vermont','Virginia','Washington','West Virginia','Wisconsin','Wyoming','District of Columbia'];
function statesFor(desc='') { return STATES.filter(s => new RegExp(`\\b${s.replace(' ','\\s+')}\\b`,'i').test(desc)); }
function nationwide(desc='') { return /nationwide|united states|across the u\.s\.|all states/i.test(desc); }
function parseDateFromText(text='') {
  const m=text.match(/(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s+(\d{4})/i);
  if (!m) return null;
  const d=new Date(`${m[1]} ${m[2]}, ${m[3]} 12:00:00 UTC`);
  return Number.isNaN(d.getTime())?null:d;
}
async function fetchHtml(url) {
  const r = await fetch(url,{headers:{'user-agent':USER_AGENT,'accept':'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8','accept-language':'en-US,en;q=0.9'}});
  if (!r.ok) throw new Error(`HTTP ${r.status} for ${url}`);
  const html=await r.text();
  const low=html.toLowerCase();
  if (low.includes('cf-chl-')||low.includes('captcha')||low.includes('verify you are human')||low.includes('access denied')) throw new Error(`Anti-bot page returned for ${url}`);
  return html;
}
function nextUrl($, current) {
  let found=null;
  $('a[href]').each((_,a)=>{
    if (found) return;
    const el=$(a), rel=(el.attr('rel')||'').toLowerCase(), text=collapse(el.text()).toLowerCase(), aria=(el.attr('aria-label')||'').toLowerCase();
    if (rel==='next'||text==='next'||text==='next →'||text==='next >'||aria.includes('next')) {
      const u=abs(el.attr('href'),current); if (u && u!==current) found=u;
    }
  });
  return found;
}
function nearestOpenContainer($, heading) {
  let cur=$(heading);
  for (let i=0;i<10;i++) {
    cur=cur.parent(); if (!cur.length) break;
    const text=collapse(cur.text());
    const count=cur.find('h3').filter((_,h)=>/Class Action Settlement/i.test(collapse($(h).text()))).length;
    if (/Payout/i.test(text)&&/Deadline/i.test(text)&&/Required\?/i.test(text)&&count===1) return cur;
  }
  return $(heading).parent();
}
function firstImage($, container, base) {
  let cur=container;
  for (let depth=0; depth<4 && cur.length; depth++,cur=cur.parent()) {
    for (const img of cur.find('img').toArray()) {
      const el=$(img); const candidates=[];
      for (const k of ['src','data-src','data-lazy-src','data-original']) if (el.attr(k)) candidates.push(el.attr(k));
      for (const k of ['srcset','data-srcset']) if (el.attr(k)) candidates.push(...el.attr(k).split(',').map(x=>x.trim().split(/\s+/)[0]).reverse());
      for (const raw of candidates) { if (!raw||raw.startsWith('data:')||/placeholder/i.test(raw)) continue; const u=abs(raw,base); if (u) return u; }
    }
  }
  return null;
}
function parseOpenPage(html,pageUrl,rankStart) {
  const $=load(html), rows=[]; let rank=rankStart;
  $('h3').each((_,h)=>{
    const title=collapse($(h).text()); if (!/Class Action Settlement/i.test(title)) return;
    const c=nearestOpenContainer($,h), text=collapse(c.text());
    if (!/Payout/i.test(text)||!/Deadline/i.test(text)) return;
    const payout=(text.match(/Payout\s+(.+?)\s+Deadline/i)||[])[1]?.trim()||null;
    const deadlineRaw=(text.match(/Deadline\s+([0-9]{1,2}\/[0-9]{1,2}\/[0-9]{2,4}|Varies)/i)||[])[1]||null;
    const proofRaw=(text.match(/Required\?\s*(Yes|No|N\/?A)/i)||[])[1]||null;
    let desc=''; if (proofRaw) {
      const idx=text.toLowerCase().indexOf(`required? ${proofRaw}`.toLowerCase()); if (idx>=0) desc=collapse(text.slice(idx+(`required? ${proofRaw}`).length).replace(/Visit Official Settlement Website.*$/i,''));
    }
    let official=null; const first=$(h).find('a[href]').first().attr('href'); if (first) official=abs(first,pageUrl);
    if (!official) { c.find('a[href]').each((_,a)=>{ if (!official && /official settlement/i.test(collapse($(a).text()))) official=abs($(a).attr('href'),pageUrl); }); }
    const deadline=isoDeadline(deadlineRaw); const status=(deadline && new Date(deadline)<new Date(new Date().toISOString().slice(0,10)+'T00:00:00Z'))?'closed':'open';
    const states=statesFor(desc);
    rows.push({id:stableId(title,official||pageUrl),title,company:companyFrom(title),shortDescription:desc,eligibilityDescription:desc||null,category:categoryFor(title,desc),payoutText:payout,deadline,proofRequired:/^yes$/i.test(proofRaw||'')?true:/^no$/i.test(proofRaw||'')?false:null,eligibleStates:states,isNationwide:nationwide(desc),classPeriodText:null,officialClaimURL:official,sourceURL:pageUrl,imageURL:firstImage($,c,pageUrl),status,createdAt:null,updatedAt:new Date().toISOString(),isFeatured:/Featured/i.test(text),sourceRank:rank++});
  });
  return {rows,next:nextUrl($,pageUrl)};
}
function nearestUpcoming($,h) { let cur=$(h); for(let i=0;i<9;i++){cur=cur.parent();if(!cur.length)break;const text=collapse(cur.text());if(cur.find('h3').length===1&&/\bby\b/i.test(text)&&text.length<1600)return cur;} return $(h).parent(); }
function parseUpcomingPage(html,pageUrl,rankStart,cutoff) {
  const $=load(html),rows=[];let rank=rankStart,dates=[];
  $('h3').each((_,h)=>{
    const title=collapse($(h).text()); if(!/settlement/i.test(title)||/\[dismissed\]/i.test(title))return;
    let article=null; for(const a of $(h).find('a[href]').toArray().concat($(h).parent().find('a[href]').toArray())){const u=abs($(a).attr('href'),pageUrl);if(u&&new URL(u).hostname.includes('classaction.org')&&new URL(u).pathname.startsWith('/news/')){article=u;break;}}
    if(!article)return; const c=nearestUpcoming($,h),text=collapse(c.text()); if(!/\bby\b/i.test(text))return;
    const published=parseDateFromText(text); if(published){dates.push(published);if(published<cutoff)return;}
    const ps=c.find('p').toArray().map(p=>collapse($(p).text())).filter(x=>x.length>=24&&x.toLowerCase()!==title.toLowerCase()&&!x.toLowerCase().startsWith('by '));
    let desc=ps.sort((a,b)=>b.length-a.length)[0]||''; const states=statesFor(desc);
    rows.push({id:stableId(title,article),title,company:companyFrom(title),shortDescription:desc,eligibilityDescription:desc||null,category:categoryFor(title,desc),payoutText:null,deadline:null,proofRequired:null,eligibleStates:states,isNationwide:nationwide(desc),classPeriodText:null,officialClaimURL:null,sourceURL:article,imageURL:firstImage($,c,pageUrl),status:'upcoming',createdAt:published?.toISOString()||null,updatedAt:(published||new Date()).toISOString(),isFeatured:false,sourceRank:rank++});
  });
  return {rows,next:nextUrl($,pageUrl),oldest:dates.length?new Date(Math.min(...dates.map(x=>x.getTime()))):null};
}
function identity(s=''){return new Set(s.toLowerCase().replace(/\$?[0-9]+(?:[.,][0-9]+)*[kmb]?\+?/g,' ').replace(/[^a-z0-9]+/g,' ').trim().split(/\s+/).filter(x=>x.length>=2&&!['class','action','settlement','settlements','lawsuit','case','ends','resolves','the','and','for','with','over'].includes(x)));}
function likelySame(a,b){const A=identity(a.title+' '+a.company),B=identity(b.title+' '+b.company);let overlap=0;for(const x of A)if(B.has(x))overlap++;const union=new Set([...A,...B]).size;return overlap>=4&&union&&overlap/union>=.42;}
async function main(){
  const open=[]; let u=OPEN_URL,visited=new Set(),rank=0,pages=0;
  while(u&&pages<MAX_OPEN_PAGES&&!visited.has(u)){visited.add(u);console.log(`Open ${pages+1}: ${u}`);const {rows,next}=parseOpenPage(await fetchHtml(u),u,rank);open.push(...rows);rank+=rows.length;pages++;u=next;if(u)await sleep(REQUEST_DELAY_MS);}
  const dedupOpen=[...new Map(open.map(x=>[x.id,x])).values()];
  const upcoming=[];u=UPCOMING_URL;visited=new Set();rank=100000;pages=0;const cutoff=new Date(Date.now()-UPCOMING_LOOKBACK_DAYS*86400000);
  while(u&&pages<MAX_UPCOMING_PAGES&&!visited.has(u)){visited.add(u);console.log(`Upcoming ${pages+1}: ${u}`);const {rows,next,oldest}=parseUpcomingPage(await fetchHtml(u),u,rank,cutoff);upcoming.push(...rows);rank+=rows.length;pages++; if(oldest&&oldest<cutoff)break;u=next;if(u)await sleep(REQUEST_DELAY_MS);}
  const uniqueUpcoming=upcoming.filter(x=>!dedupOpen.some(o=>likelySame(x,o)));
  const settlements=[...dedupOpen,...uniqueUpcoming];
  const template=JSON.parse(await fs.readFile(TEMPLATE,'utf8'));
  template.appConfig.settlementScanner.maxPages=5; template.appConfig.settlementScanner.upcomingMaxPages=3; template.appConfig.settlementScanner.useFirebaseCatalog=true; template.appConfig.settlementScanner.catalogSourceMode='firebase'; template.appConfig.settlementScanner.allowDeviceFallback=true;
  template.settlementCatalog.current={schemaVersion:1,updatedAt:new Date().toISOString(),sourceURL:OPEN_URL,count:settlements.length,settlements};
  await fs.writeFile(OUTPUT,JSON.stringify(template,null,2)+'\n');
  console.log(`DONE: ${dedupOpen.length} open + ${uniqueUpcoming.length} upcoming = ${settlements.length}`);
  console.log(`File: ${path.resolve(new URL(OUTPUT).pathname)}`);
}
main().catch(e=>{console.error(e);process.exit(1)});
