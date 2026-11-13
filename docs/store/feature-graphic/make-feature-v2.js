// v2b — one SVG, embedded base64 art, clipPath squircle, quieter echo.
const sharp = require('/workspace/Workspace/tmp/svgwork/node_modules/sharp');
const fs = require('fs');
const BRAND = '/workspace/Workspace/budget-project/local-budget-app/docs/brand';
const FG = '/workspace/Workspace/budget-project/local-budget-app/app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png';
const PAPER = '#F4F1EA', STEEL = '#37474F', BODY = '#5A6B75';
const NAME = 'Steiner Budget';
const SHORT = 'Budget by hand, keep every receipt —';
const SHORT2 = 'nothing leaves unless you send it.';

(async () => {
  const icon64 = await sharp(`${BRAND}/icon-play-512.png`).resize(260, 260)
    .png().toBuffer({ resolveWithObject: false }).then(b => b.toString('base64'));
  const mark64 = await sharp(FG).tint({ r: 214, g: 228, b: 219 })
    .resize(260, 260).png().toBuffer().then(b => b.toString('base64'));
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <rect width="1024" height="500" fill="${PAPER}"/>
  <image href="data:image/png;base64,${mark64}" x="700" y="150" width="260" height="260" opacity="0.55"/>
  <defs><clipPath id="sq"><rect x="88" y="138" width="230" height="230" rx="51"/></clipPath></defs>
  <image href="data:image/png;base64,${icon64}" x="88" y="138" width="230" height="230" clip-path="url(#sq)"/>
  <text x="352" y="215" font-family="Liberation Sans" font-weight="bold" font-size="64" fill="${STEEL}">${NAME}</text>
  <rect x="354" y="243" width="88" height="5" fill="${STEEL}" opacity="0.55"/>
  <text x="352" y="300" font-family="Liberation Sans" font-size="29" fill="${BODY}">${SHORT}</text>
  <text x="352" y="340" font-family="Liberation Sans" font-size="29" fill="${BODY}">${SHORT2}</text>
</svg>`;
  await sharp(Buffer.from(svg), { density: 288 }).resize(1024, 500).png()
    .toFile('/workspace/Workspace/tmp/featgfx-v2/feature-graphic-free-v2b.png');
  console.log('v2b written');
})();
