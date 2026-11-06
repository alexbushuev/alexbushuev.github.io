// Pulls every portable number out of the 2D game source into plain JSON.
// Run once; afterwards data/ is the source of truth for the 3D version.
const fs = require('fs'), path = require('path'), vm = require('vm');
const [src, out] = process.argv.slice(2);
const text = fs.readFileSync(src, 'utf8');
const a = text.indexOf('const SEG=200'), b = text.indexOf('function buildColors(T)');
if (a < 0 || b < 0) throw new Error('markers not found');
const code = text.slice(a, b) + `;({CATS,TRACKS,BIKES,SUITS,HELMETS,GEAR_COLORS,PAINTS,WEAPONS,KICK,CHARS,THEMES,FALL_K,PLACE_SHARE,LV_COST,MAX_LV,GEAR_COST,DEFAULT_KEYS})`;
const d = vm.runInNewContext(code, { Math, Object, Array, JSON, String, Number });
// which roadside things are solid: read from the 2D sprite table
const hit = {}; const c = text.slice(text.indexOf('function buildSprites(T)'), text.indexOf('const flipped='));
for (const m of c.matchAll(/(\w+):\{[^{}]*?hit:([\d.]+)/g)) hit[m[1]] = +m[2];
const files = {
  leagues: d.CATS, tracks: d.TRACKS, bikes: d.BIKES,
  gear: { suits: d.SUITS, helmets: d.HELMETS, colors: d.GEAR_COLORS, paints: d.PAINTS, weapons: d.WEAPONS, kick: d.KICK },
  rivals: d.CHARS, themes: d.THEMES, decor_hit: hit,
  rules: { fall_k: d.FALL_K, place_share: d.PLACE_SHARE, upgrade_cost: d.LV_COST, max_level: d.MAX_LV, gear_cost: d.GEAR_COST, keys: d.DEFAULT_KEYS }
};
for (const k in files) fs.writeFileSync(path.join(out, k + '.json'), JSON.stringify(files[k], null, 1) + '\n');
console.log(Object.keys(files).map(k => k + ':' + JSON.stringify(files[k]).length).join(' '));
console.log('decor_hit', JSON.stringify(hit));
