const sharp=require('/workspace/Workspace/tmp/svgwork/node_modules/sharp');
const STEEL='#37474F',PAPER='#F4F1EA',DEEP='#263238',AMBER='#F9A825';
const NAME='Steiner Budget';
const SHORT='Budget by hand, keep every receipt —';
const SHORT2='your data never leaves your phone.';
function tile(x,y,s,tier){
  const ground=tier==='free'?PAPER:DEEP, glyph=tier==='free'?STEEL:PAPER, acc=tier==='pro'?AMBER:STEEL;
  const r=s*0.15; // squircle corner ~0.2237*? use icon-like rounded square
  return `<g transform="translate(${x},${y}) scale(${s/100})">
   <rect width="100" height="100" rx="22" fill="${ground}"/>
   <g stroke="${glyph}" stroke-width="6" fill="none" stroke-linejoin="miter">
     <path d="M24 44 L50 20 L76 44"/><path d="M30 41 L30 78 L70 78 L70 41"/></g>
   <circle cx="50" cy="60" r="15" fill="${acc}"/>
   <text x="50" y="59.25" font-family="Liberation Sans" font-weight="bold" font-size="25" fill="${ground}" text-anchor="middle" dominant-baseline="central">$</text></g>`;
}
function art(tier){
  // right-side decorative echo: two faint house chevrons (vault family texture)
  const faint=tier==='free'?'#DEDAD0':'#33404A';
  return `<g stroke="${faint}" stroke-width="7" fill="none">
   <path d="M760 120 L880 6 L1000 120"/><path d="M792 108 L792 260 L968 260 L968 108" opacity="0.55"/></g>
   <circle cx="880" cy="190" r="34" fill="${faint}" opacity="0.85"/>`;
}
function graphic(tier){
  const bg=tier==='free'?PAPER:DEEP;
  const nameC=tier==='free'?STEEL:PAPER;
  const bodyC=tier==='free'?'#5A6B75':'#AEBDC7';
  const rule=tier==='free'?'#C9C4B8':'#3B4A54';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <rect width="1024" height="500" fill="${bg}"/>
  ${art(tier)}
  ${tile(88,138,230,tier)}
  <text x="322" y="215" font-family="Liberation Sans" font-weight="bold" font-size="64" fill="${nameC}">${NAME}</text>
  <rect x="324" y="243" width="88" height="5" fill="${tier==='free'?STEEL:PAPER}" opacity="0.55"/>
  <text x="322" y="300" font-family="Liberation Sans" font-size="29" fill="${bodyC}">${SHORT}</text>
  <text x="322" y="340" font-family="Liberation Sans" font-size="29" fill="${bodyC}">${SHORT2}</text>
</svg>`;
}
(async()=>{
  for(const t of ['free','pro']){
    await sharp(Buffer.from(graphic(t)),{density:288}).resize(1024,500).png().toFile(`/workspace/Workspace/tmp/featgfx/feature-graphic-${t}.png`);
  }
  console.log('feature graphics ok');
})();
