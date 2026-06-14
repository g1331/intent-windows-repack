const fs = require('fs');
const path = require('path');
const nm = process.argv[2];
const outFile = process.argv[3];
const lines = [];
const log = (s) => lines.push(s);

log('runtime: electron=' + process.versions.electron +
    ' node=' + process.versions.node +
    ' modules(ABI)=' + process.versions.modules +
    ' platform=' + process.platform + ' arch=' + process.arch);
log('---');

const tests = {
  'better-sqlite3 (replaced->win)': 'better-sqlite3/build/Release/better_sqlite3.node',
  'sharp           (added->win)':   '@img/sharp-win32-x64/lib/sharp-win32-x64.node',
  'parcel-watcher  (added->win)':   '@parcel/watcher/node_modules/@parcel/watcher-win32-x64/watcher.node',
  'node-pty        (still darwin)': 'node-pty/build/Release/pty.node',
  'ssh2 sshcrypto  (still darwin)': 'ssh2/lib/protocol/crypto/build/Release/sshcrypto.node',
  'cpu-features    (still darwin)': 'cpu-features/build/Release/cpufeatures.node',
};

for (const [name, rel] of Object.entries(tests)) {
  const full = path.join(nm, rel);
  if (!fs.existsSync(full)) { log('MISS  ' + name + '  ::  file not found'); continue; }
  try {
    process.dlopen({ exports: {} }, full);
    log('OK    ' + name);
  } catch (e) {
    log('FAIL  ' + name + '  ::  ' + String(e.message).split('\n')[0]);
  }
}

fs.writeFileSync(outFile, lines.join('\r\n'), 'utf8');
