const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');
const embedded = fs.readFileSync(path.join(root, 'node_modules/trix/dist/trix.umd.min.js'), 'utf8').match(/DOMPurify ([\d.]+)/);
const purify = require(path.join(root, 'node_modules/dompurify/package.json'));
if (!embedded || embedded[1] !== purify.version) {
  throw new Error('Trix bundles a different DOMPurify version than the audited lockfile; update the Trix release');
}
const files = {
  'dist/trix.umd.min.js': 'vendor/assets/javascripts/trix.js',
  'dist/trix.css': 'vendor/assets/stylesheets/trix.css',
  'LICENSE': 'vendor/trix-LICENSE'
};
for (const [source, target] of Object.entries(files)) {
  const contents = fs.readFileSync(path.join(root, 'node_modules/trix', source));
  const destination = path.join(root, target);
  if (process.argv.includes('--check')) {
    if (!contents.equals(fs.readFileSync(destination))) {
      throw new Error(`${target} differs from the locked Trix package; run npm run vendor:trix`);
    }
  } else {
    fs.writeFileSync(destination, contents);
  }
}

const license = fs.readFileSync(path.join(root, 'node_modules/dompurify/LICENSE'));
const licensePath = path.join(root, 'vendor/dompurify-LICENSE');
if (process.argv.includes('--check')) {
  if (!license.equals(fs.readFileSync(licensePath))) throw new Error('DOMPurify license is out of date');
} else {
  fs.writeFileSync(licensePath, license);
}
