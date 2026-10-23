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
    const list = [];
    if (process.env.USERPROFILE) {
      list.push(path.join(process.env.USERPROFILE, 'OneDrive', 'Documents', 'MuseScore4', 'Plugins'));
      list.push(path.join(process.env.USERPROFILE, 'Documents', 'MuseScore4', 'Plugins'));
      list.push(path.join(process.env.USERPROFILE, 'OneDrive', 'Documents', 'MuseScore3', 'Plugins'));
      list.push(path.join(process.env.USERPROFILE, 'Documents', 'MuseScore3', 'Plugins'));
    }
    list.push(path.join(HOME, 'OneDrive', 'Documents', 'MuseScore4', 'Plugins'));
    list.push(path.join(HOME, 'Documents', 'MuseScore4', 'Plugins'));
    list.push(path.join(process.env.LOCALAPPDATA || path.join(HOME, 'AppData', 'Local'), 'MuseScore', 'MuseScore4', 'plugins'));
    list.push(path.join(HOME, 'Documents', 'MuseScore3', 'Plugins'));
    return [...new Set(list)];
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

// Find existing paths or choose preferred default
function resolveTargetDirectories() {
  const candidates = getCandidatePluginPaths();
  const existing = candidates.filter(p => fs.existsSync(p));

  if (existing.length === 0) {
    return [path.join(candidates[0], 'MuseCollab')];
  }

  const targets = [];
  for (const p of existing) {
    targets.push(path.join(p, 'MuseCollab'));
    const lower = path.join(p, 'Musecollab');
    if (fs.existsSync(lower)) {
      targets.push(lower);
    }
  }
  return [...new Set(targets)];
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

const targetDirs = resolveTargetDirectories();
console.log(`Target directories found: ${targetDirs.length}`);
for (const t of targetDirs) {
  console.log(` -> ${t}`);
}

try {
  for (const t of targetDirs) {
    console.log(`Copying plugin files to: ${t}…`);
    copyDirectorySync(SOURCE_DIR, t);
  }

  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║        ✅  MuseCollab Plugin Installed Successfully!           ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  for (const t of targetDirs) {
    console.log(`📁 Installed at: ${t}`);
  }
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
