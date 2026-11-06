// Steiner Budget icon sheet — same architecture as home-vault-app's make-sheet.js:
// icons are hand-authored SVG, rasterized with sharp, masks as data-URI <image>.
// Fonts: Liberation Sans via FONTCONFIG_FILE pointing at browserenv copy.
const sharp=require('/workspace/Workspace/tmp/svgwork/node_modules/sharp');
const fs=require('fs');
const STEEL='#37474F',PAPER='#F4F1EA',DEEP='#263238',AMBER='#F9A825',MUT='#546E7A';
function iconSvg(tier,mark){
  const ground=tier==='free'?PAPER:DEEP, glyph=tier==='free'?STEEL:PAPER, acc=tier==='pro'?AMBER:STEEL;
  const dollar=mark?`<text x="44" y="61" font-family="Liberation Sans" font-weight="bold" font-size="22" fill="${ground}" text-anchor="middle" dominant-baseline="central">$</text>`:'';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect width="100" height="100" fill="${ground}"/>
  <path d="M24 44 L50 20 L76 44" fill="none" stroke="${glyph}" stroke-width="6" stroke-linejoin="miter"/>
  <path d="M30 41 L30 78 L70 78 L70 41" fill="none" stroke="${glyph}" stroke-width="6"/>
  <circle cx="44" cy="61" r="13.5" fill="${acc}"/>${dollar}
  <circle cx="60" cy="69" r="10.2" fill="${ground}"/>
  <circle cx="60" cy="69" r="7.8" fill="none" stroke="${acc}" stroke-width="3"/>
</svg>`;
}
const maskSvg=(px,shape)=> shape==='ci'
 ? `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}"><circle cx="${px/2}" cy="${px/2}" r="${px/2}" fill="#fff"/></svg>`
 : `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}"><rect width="${px}" height="${px}" rx="${(px*0.2237).toFixed(1)}" fill="#fff"/></svg>`;
async function iconPng(tier,mark,size,shape){
  const px=size*4;
  const icon=await sharp(Buffer.from(iconSvg(tier,mark)),{density:384}).resize(px,px).png().toBuffer();
  if(!shape) return 'data:image/png;base64,'+icon.toString('base64');
  const mask=await sharp(Buffer.from(maskSvg(px,shape))).png().toBuffer();
  const out=await sharp(icon).composite([{input:mask,blend:'dest-in'}]).png().toBuffer();
  return 'data:image/png;base64,'+out.toString('base64');
}
(async()=>{
  const W=1160,ROW=180,TOP=96,rows2=['plain','dollar'];
  const H=TOP+ROW*rows2.length+20;
  let body='';
  for(let r=0;r<rows2.length;r++){
    const mark=rows2[r]==='dollar'; const y=TOP+ROW*r;
    body+=`<text x="44" y="${y+34}" font-family="Liberation Sans" font-weight="bold" font-size="19" fill="${STEEL}">Hearth · ${mark?'$ pair (marked)':'plain pair (unmarked)'}</text>`;
    body+=`<text x="44" y="${y+56}" font-family="Liberation Sans" font-size="12" fill="${MUT}">${mark?'typographic $ knockout — reads dollar to 32 px':'currency-neutral baseline'}</text>`;
    const cells=[[96,'free',''],['96','pro',''],[96,'free','ci'],[96,'pro','sq'],[0,0,0],[0,0,0]];
    const xs=[330,582,834,950];
    for(let c=0;c<4;c++){
      const [,tier,shape]=cells[c];
      const uri=await iconPng(tier,mark,96,shape);
      const wx=c<2?(tier==='free'?'#E8E8E6':'#3B4750'):'#D6D6D4';
      if(c<2){body+=`<rect x="${xs[c]-8}" y="${y+66}" width="124" height="106" rx="10" fill="${wx}"/>`;}
      body+=`<image href="${uri}" x="${xs[c]}" y="${y+70}" width="96" height="96"/>`;
      if(c===0)body+=`<text x="${xs[c]+48}" y="${y+176}" font-family="Liberation Sans" font-size="11" fill="${MUT}" text-anchor="middle">96 px · light</text>`;
      if(c===1)body+=`<text x="${xs[c]+48}" y="${y+176}" font-family="Liberation Sans" font-size="11" fill="${MUT}" text-anchor="middle">96 px · dark</text>`;
      if(c===2)body+=`<text x="${xs[c]+48}" y="${y+176}" font-family="Liberation Sans" font-size="11" fill="${MUT}" text-anchor="middle">circle</text>`;
      if(c===3)body+=`<text x="${xs[c]+48}" y="${y+176}" font-family="Liberation Sans" font-size="11" fill="${MUT}" text-anchor="middle">squircle</text>`;
    }
    // 48/32 raw pair on neutral
    const x48=1052;
    for(const [sz,dy] of [[48,0],[32,60]]){
      for(let k=0;k<2;k++){
        const uri=await iconPng(k?'pro':'free',mark,sz,'');
        body+=`<image href="${uri}" x="${x48+k*(sz+8)}" y="${y+70+dy}" width="${sz}" height="${sz}"/>`;
      }
    }
    body+=`<text x="${x48+40}" y="${y+176}" font-family="Liberation Sans" font-size="11" fill="${MUT}" text-anchor="middle">48 / 32 px</text>`;
  }
  const master=`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">
  <rect width="${W}" height="${H}" fill="#FFFFFF"/>
  <text x="44" y="44" font-family="Liberation Sans" font-weight="bold" font-size="22" fill="${STEEL}">Steiner Budget — Hearth finalists (SVG pipeline, real typography)</text>
  <text x="44" y="68" font-family="Liberation Sans" font-size="13" fill="${MUT}">Vault-architecture sheet: hand-authored SVG → sharp 4× → masks as bitmaps. Free = paper/steel, Pro = inverted + amber.</text>
  ${body}</svg>`;
  await sharp(Buffer.from(master),{density:144}).png().toFile('/workspace/Workspace/tmp/budgetsvg/hearth-sheet.png');
  // tiles for repo
  for(const mark of [true,false]) for(const tier of ['free','pro']){
    const uri=await iconPng(tier,mark,512,'');
    fs.writeFileSync(`/workspace/Workspace/tmp/budgetsvg/hearth-${mark?'dollar':'plain'}-${tier}.png`,Buffer.from(uri.split(',')[1],'base64'));
  }
  console.log('sheet + tiles ok');
})();
