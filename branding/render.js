// Rasterize the brand SVGs to the PNGs the build needs.
// Usage: node render.js   (run from the branding/ folder)
const sharp = require('sharp');
const fs = require('fs');

const LOGO = 'logo-magicpaste.svg';   // 1024x1024, violet bg + symbol
const GLYPH = 'glifo-magicpaste.svg'; // transparent symbol only

async function png(src, size, out, opts = {}) {
  let img = sharp(src, { density: 384 }).resize(size, size, {
    fit: 'contain',
    background: opts.bg || { r: 0, g: 0, b: 0, alpha: 0 },
  });
  await img.png().toFile(out);
  console.log('  ->', out, size + 'x' + size);
}

(async () => {
  // Master logos (full, with violet bg)
  await png(LOGO, 1024, 'out/logo_1024.png');
  await png(LOGO, 512, 'out/logo_512.png');
  await png(LOGO, 256, 'out/logo_256.png');

  // Glyph only (transparent) — for adaptive icon foreground & splash
  await png(GLYPH, 1024, 'out/glyph_1024.png');
  await png(GLYPH, 512, 'out/glyph_512.png');

  console.log('done');
})().catch(e => { console.error(e); process.exit(1); });
