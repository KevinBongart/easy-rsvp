const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const root = path.join(__dirname, '..');
const trix = require(path.join(root, 'node_modules/trix/package.json'));
const purify = require(path.join(root, 'node_modules/dompurify/package.json'));
const buildDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'easy-rsvp-trix-'));
const sourceArchive = path.join(buildDirectory, 'trix.tar.gz');
const sourceUrl = `https://github.com/basecamp/trix/archive/refs/tags/v${trix.version}.tar.gz`;
const sourceChecksum = '896c510cb1f44fd1ab9e40d2e1c7275270aaeb807310b4c74dbf5bdf65100b6c';
execFileSync('curl', ['-fsSL', sourceUrl, '-o', sourceArchive]);
const downloadedChecksum = crypto.createHash('sha256').update(fs.readFileSync(sourceArchive)).digest('hex');
if (downloadedChecksum !== sourceChecksum) throw new Error('Trix source archive checksum mismatch');
execFileSync('tar', ['-xzf', sourceArchive, '-C', buildDirectory]);
const sourceRoot = path.join(buildDirectory, `trix-${trix.version}`);
const javascript = path.join(buildDirectory, 'trix.js');
execFileSync(path.join(root, 'node_modules/esbuild/bin/esbuild'), [
  path.join(sourceRoot, 'src/trix/trix.js'),
  '--bundle', '--format=iife', '--minify', '--target=es2018', '--legal-comments=inline',
  `--alias:trix=./trix-${trix.version}/src/trix`,
  `--alias:trix_editor_element=./trix-${trix.version}/src/trix/elements/trix_editor_element.js`,
  `--alias:trix_toolbar_element=./trix-${trix.version}/src/trix/elements/trix_toolbar_element.js`,
  `--alias:dompurify=${path.join(root, 'node_modules/dompurify/dist/purify.es.mjs')}`,
  `--banner:js=/* Trix ${trix.version}; DOMPurify ${purify.version} */`,
  `--outfile=${javascript}`
], { cwd: buildDirectory });

const files = {
  'app/assets/javascripts/trix.js': fs.readFileSync(javascript),
  'app/assets/stylesheets/trix.css': fs.readFileSync(path.join(root, 'node_modules/trix/dist/trix.css'))
};
for (const [target, contents] of Object.entries(files)) {
  const destination = path.join(root, target);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, contents);
}
fs.rmSync(buildDirectory, { recursive: true });
