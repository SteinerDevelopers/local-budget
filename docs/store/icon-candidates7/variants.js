const STEEL='#37474F',PAPER='#F4F1EA',DEEP='#263238',AMBER='#F9A825';
// every variant returns inner SVG for a 100-viewBox; fg knockout semantics not needed at concept stage
function svg(tier,inner,bg=true){
  const ground=tier==='free'?PAPER:DEEP;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">${bg?`<rect width="100" height="100" fill="${ground}"/>`:''}${inner}</svg>`;
}
function C(tier){return {g:tier==='free'?STEEL:PAPER,b:tier==='free'?PAPER:DEEP,a:tier==='pro'?AMBER:STEEL};}
const HOUSE_OVERHANG=(s,c)=>`<path d="M24 44 L50 20 L76 44" fill="none" stroke="${s.g}" stroke-width="${s.sw||6}" stroke-linejoin="miter"/><path d="M30 41 L30 78 L70 78 L70 41" fill="none" stroke="${s.g}" stroke-width="${s.sw||6}"/>`;
const PENT=(s,w=6)=>`<path d="M30 42 L50 23 L70 42 L70 77 L30 77 Z" fill="none" stroke="${s.g}" stroke-width="${w}" stroke-linejoin="round"/>`;
const DOLLAR=(x,y,fs,fill)=>`<text x="${x}" y="${y}" font-family="Liberation Sans" font-weight="bold" font-size="${fs}" fill="${fill}" text-anchor="middle" dominant-baseline="central">$</text>`;
const V={};
// 1 baseline (current committed)
V['1 baseline']=t=>{const s=C(t);return svg(t,`${HOUSE_OVERHANG({g:s.g},{sw:6})}<circle cx="44" cy="61" r="13.5" fill="${s.a}"/>${DOLLAR(44,61,22,s.b)}<circle cx="60" cy="69" r="10.2" fill="${s.b}"/><circle cx="60" cy="69" r="7.8" fill="none" stroke="${s.a}" stroke-width="3"/>`);};
// 2 solo big coin, closed pentagon house
V['2 solo coin']=t=>{const s=C(t);return svg(t,`${PENT(s,6)}<circle cx="50" cy="60" r="15.5" fill="${s.a}"/>${DOLLAR(50,60,27,s.b)}`);};
// 3 negative: solid house, coin cut out, $ in hole
V['3 negative coin']=t=>{const s=C(t);const holeFill=t==='free'?PAPER:DEEP;
  return svg(t,`<path d="M30 42 L50 23 L70 42 L70 77 L30 77 Z" fill="${s.g}" stroke="none"/><circle cx="50" cy="58" r="15" fill="${holeFill}"/>${DOLLAR(50,58,26,t==='free'?s.g:AMBER)}`);};
// 4 heavier stroke, single coin on baseline
V['4 heavy line']=t=>{const s=C(t);return svg(t,`${HOUSE_OVERHANG({g:s.g,sw:7.5})}<circle cx="50" cy="61" r="14.5" fill="${s.a}"/>${DOLLAR(50,61,25,s.b)}`);};
// 5 coin sunk into floor (money inside the house)
V['5 floor coin']=t=>{const s=C(t);return svg(t,`${HOUSE_OVERHANG({g:s.g})}<circle cx="50" cy="72" r="15" fill="${s.a}"/><clipPath id="cf"><rect x="0" y="0" width="100" height="77.5"/></clipPath><g clip-path="url(#cf)"><circle cx="50" cy="72" r="15" fill="${s.a}"/>${DOLLAR(50,69,25,s.b)}</g>${DOLLAR(50,68,25,s.b)}`);};
// 6 open house (gap in base — lighter, airier)
V['6 open house']=t=>{const s=C(t);return svg(t,`<path d="M26 45 L50 21 L74 45" fill="none" stroke="${s.g}" stroke-width="6" stroke-linejoin="miter"/><path d="M32 42 L32 76 M68 42 L68 76" stroke="${s.g}" stroke-width="6"/><circle cx="50" cy="60" r="14" fill="${s.a}"/>${DOLLAR(50,60,24,s.b)}`);};
// 7 pair, both coins solid, tidy horizontal alignment at floor
V['7 tidy pair']=t=>{const s=C(t);return svg(t,`${HOUSE_OVERHANG({g:s.g})}<circle cx="41.5" cy="66" r="11.5" fill="${s.a}"/>${DOLLAR(41.5,66,20,s.b)}<circle cx="59" cy="66" r="11.5" fill="${s.a}" opacity="${t==='free'?1:0.35}"/>${t==='pro'?`<circle cx="59" cy="66" r="11.5" fill="none" stroke="${s.a}" stroke-width="0"/>`:''}`);};
// 8 roof bar + single coin: closed house, roof filled solid — strongest silhouette
V['8 solid roof']=t=>{const s=C(t);return svg(t,`<path d="M22 45 L50 19 L78 45 Z" fill="${s.g}"/><path d="M31 45 L31 78 L69 78 L69 45" fill="none" stroke="${s.g}" stroke-width="6"/><circle cx="50" cy="62" r="13.5" fill="${s.a}"/>${DOLLAR(50,62,23,s.b)}`);};
module.exports={V,svg};
