#!/usr/bin/env node

/**
 * MuseCollab — 1-Click Automatic Plugin Installer
 * Cross-platform installer for macOS, Windows, and Linux.
 * Detects MuseScore plugin directory, creates it if missing, and copies files.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const HOME = os.homedir();
const PLATFORM = os.platform(); // 'win32', 'darwin', 'linux'

// Source folder is the `plugin/` directory next to this script
const SOURCE_DIR = path.resolve(__dirname, 'plugin');

if (!fs.existsSync(SOURCE_DIR)) {
  console.error('❌ Error: Could not find plugin directory at: ' + SOURCE_DIR);
  process.exit(1);
}

// Common MuseScore 4 and 3 plugin locations per OS
function getCandidatePluginPaths() {
  if (PLATFORM === 'win32') {
    return [
      path.join(HOME, 'Documents', 'MuseScore4', 'Plugins'),
      path.join(process.env.LOCALAPPDATA || path.join(HOME, 'AppData', 'Local'), 'MuseScore', 'MuseScore4', 'plugins'),
      path.join(HOME, 'Documents', 'MuseScore3', 'Plugins'),
    ];
  } else if (PLATFORM === 'darwin') {
    return [
      path.join(HOME, 'Documents', 'MuseScore4', 'Plugins'),
      path.join(HOME, 'Library', 'Audio', 'Plug-Ins', 'MuseScore4', 'Plugins'),
      path.join(HOME, 'Library', 'Application Support', 'MuseScore', 'MuseScore4', 'plugins'),
      path.join(HOME, 'Documents', 'MuseScore3', 'Plugins'),
    ];
  } else {
    // Linux
    return [
      path.join(HOME, 'Documents', 'MuseScore4', 'Plugins'),
      path.join(HOME, '.local', 'share', 'MuseScore', 'MuseScore4', 'plugins'),
      path.join(HOME, 'Documents', 'MuseScore3', 'Plugins'),
    ];
  }
}

// Find existing path or choose preferred default
function resolveTargetDirectory() {
  const candidates = getCandidatePluginPaths();

  // Pick first one that already exists
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return path.join(p, 'MuseCollab');
    }
  }

  // If none exists yet, use the primary Documents location and create it
  return path.join(candidates[0], 'MuseCollab');
}

// Recursive directory copy
function copyDirectorySync(src, dest) {
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(dest, { recursive: true });
  }

  const entries = fs.readdirSync(src, { withFileTypes: true });

  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      copyDirectorySync(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

console.log('\n🎵  MuseCollab 1-Click Installer');
console.log('=================================');
console.log(`Detected OS: ${PLATFORM === 'darwin' ? 'macOS' : PLATFORM === 'win32' ? 'Windows' : 'Linux'}`);

const targetDir = resolveTargetDirectory();
console.log(`Target directory: ${targetDir}`);

try {
  console.log('Copying plugin files…');
  copyDirectorySync(SOURCE_DIR, targetDir);

  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║        ✅  MuseCollab Plugin Installed Successfully!           ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log(`\n📁 Location: ${targetDir}`);
  console.log('🌐 Server:   https://musescore-collab.onrender.com (Pre-configured!)\n');
  console.log('👉 Quick 2-step activation in MuseScore:');
  console.log('   1. Open MuseScore 4 (or 3)');
  console.log('   2. Go to: Plugins → Manage Plugins (or Preferences → Plugins)');
  console.log('   3. Check [✓] MuseCollab');
  console.log('   4. Open from top menu: Plugins → MuseCollab\n');
} catch (err) {
  console.error('\n❌ Installation failed:', err.message || err);
  process.exit(1);
}
