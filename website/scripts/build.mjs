import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('../', import.meta.url));
const dist = path.join(root, 'dist');
const release = JSON.parse(await fs.readFile(path.join(root, 'release.json'), 'utf8'));
if (!/^\d+\.\d+\.\d+$/.test(release.version) || release.filename !== `Foglio-${release.version}.dmg`) {
  throw new Error('release.json must identify a versioned Foglio DMG.');
}
const source = path.join(root, '..', 'build', release.filename);
const binary = await fs.readFile(source).catch(() => { throw new Error(`Missing ${release.filename}. Build that release with scripts/dmg.sh first.`); });
if (binary.length < 512 || binary.subarray(-512, -508).toString('ascii') !== 'koly') {
  throw new Error('The download is not a complete UDIF disk image.');
}
const checksum = `${createHash('sha256').update(binary).digest('hex')}  ${release.filename}\n`;
const downloads = path.join(root, 'downloads');
await fs.mkdir(downloads, { recursive: true });
await fs.writeFile(path.join(downloads, release.filename), binary);
await fs.writeFile(path.join(downloads, release.filename + '.sha256.txt'), checksum);

// Reuse directories: some local permission profiles allow file replacement
// but prohibit removing directories, including generated build folders.
async function clearFiles(directory) {
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    const location = path.join(directory, entry.name);
    if (entry.isDirectory()) await clearFiles(location);
    else await fs.unlink(location);
  }
}
await fs.mkdir(dist, { recursive: true });
await clearFiles(dist);
let html = await fs.readFile(path.join(root, 'index.html'), 'utf8');
html = html.replaceAll(/Foglio-\d+\.\d+\.\d+\.dmg/g, release.filename)
  .replaceAll(/(<span data-version>)[^<]+/g, `$1${release.version}`);
await fs.writeFile(path.join(dist, 'index.html'), html);
await fs.copyFile(path.join(root, 'styles.css'), path.join(dist, 'styles.css'));
await fs.copyFile(path.join(root, 'app.js'), path.join(dist, 'app.js'));
await fs.writeFile(path.join(dist, 'release.json'), JSON.stringify({ ...release, bytes: binary.length, sha256: checksum.split(' ')[0] }, null, 2) + '\n');
for (const directory of ['images', 'fonts']) {
  await fs.cp(path.join(root, 'assets', directory), path.join(dist, 'assets', directory), { recursive: true });
}
await fs.mkdir(path.join(dist, 'downloads'), { recursive: true });
await fs.copyFile(path.join(downloads, release.filename), path.join(dist, 'downloads', release.filename));
await fs.copyFile(path.join(downloads, release.filename + '.sha256.txt'), path.join(dist, 'downloads', release.filename + '.sha256.txt'));
console.log(`Built website/dist — Foglio ${release.version}, ${(binary.length / 1024 / 1024).toFixed(2)} MiB DMG, SHA-256 included.`);
