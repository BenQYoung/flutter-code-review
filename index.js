// flutter-code-review
// Install via: npm install @benqyoung/flutter-code-review
// Then run: npx flutter-review-install-claude  or  npx flutter-review-install-cursor

const { execSync } = require('child_process');
const path = require('path');

module.exports = {
  installClaude: () => execSync(`bash ${path.join(__dirname, 'scripts/install-claude.sh')}`, { stdio: 'inherit' }),
  installCursor: () => execSync(`bash ${path.join(__dirname, 'scripts/install-cursor.sh')}`, { stdio: 'inherit' }),
};
