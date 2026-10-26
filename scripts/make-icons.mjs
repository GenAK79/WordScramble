// Regenerates the PNG icons from public/icon.svg. Needs `sharp` (npm i -D sharp).
import sharp from 'sharp';
import { readFileSync } from 'node:fs';
const svg = readFileSync(new URL('../public/icon.svg', import.meta.url));
for (const [name, size] of [['icon-192.png', 192], ['icon-512.png', 512], ['apple-touch-icon.png', 180]]) {
  await sharp(svg, { density: 384 }).resize(size, size).png().toFile(new URL(`../public/${name}`, import.meta.url).pathname);
  console.log('wrote', name);
}
