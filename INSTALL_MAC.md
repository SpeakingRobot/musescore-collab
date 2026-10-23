# 🍎 MuseCollab — Complete Mac Installation & Setup Guide

This guide covers installing and using **MuseCollab** on macOS (Apple Silicon M1/M2/M3/M4 and Intel Macs) for **MuseScore 4** and **MuseScore 3**.

---

## ⚡ Method 1: 1-Click Install via Finder (Easiest)

1. Download or clone this repository to your Mac.
2. In **Finder**, double-click **`install.command`**.
   > *Tip: If macOS Gatekeeper shows a popup saying "cannot be opened because it is from an unidentified developer":*  
   > Right-click (or Control-click) on **`install.command`** → click **Open** → then click **Open** in the dialog.
3. The installer automatically finds your MuseScore plugins folder (creating it if needed) and installs MuseCollab.
4. Press Enter to close when it says **`[OK] Installed Successfully!`**.

---

## 💻 Method 2: 1-Line Terminal Install

Open **Terminal** (press `Cmd + Space`, type `Terminal`, and press Enter), then run:

```bash
cd /path/to/musescore-collab
./install.sh
```

Or copy the files directly in one line without running scripts:

```bash
mkdir -p ~/Documents/MuseScore4/Plugins/MuseCollab && cp -R plugin/. ~/Documents/MuseScore4/Plugins/MuseCollab/
```

*(For MuseScore 3: replace `MuseScore4` with `MuseScore3` in the command above).*

---

## 🖱️ Method 3: Manual Drag-and-Drop (Finder)

If you prefer doing it manually by hand:

1. Open **Finder**.
2. Press `Cmd + Shift + G` (Go to Folder).
3. Paste:
   ```text
   ~/Documents/MuseScore4/Plugins
   ```
   *(If the folder doesn't exist, go to `~/Documents` and create `MuseScore4` then `Plugins` inside it).*
4. Create a new folder inside called **`MuseCollab`**.
5. Copy all files from the `plugin` folder of this repo into that `MuseCollab` folder.

You should have:
```text
~/Documents/MuseScore4/Plugins/MuseCollab/
├── CollabPlugin.qml
├── js/
│   ├── api.js
│   ├── mscxParser.js
│   └── scoreWriter.js
└── ui/
    ├── BranchPanel.qml
    ├── DiffViewer.qml
    ├── LivePanel.qml
    ├── MeasurePicker.qml
    └── SettingsPanel.qml
```

---

## 🚀 How to Enable in MuseScore on macOS

1. Open **MuseScore** on your Mac.
2. Look at the top macOS menu bar (next to the 🍎 Apple icon):
   - In MuseScore 4: click **Plugins → Manage Plugins…**  
   - *(Or click **MuseScore → Preferences…** → click the **Plugins** tab)*
3. Find **MuseCollab** in the list.
4. Tick the checkbox **[✓]** next to it and click **OK**.
5. Go to the top menu: **Plugins → MuseCollab**.
6. The MuseCollab panel docks on the right side of your score!

---

## 🎵 Getting Started on Mac

1. Open your score.
2. In the MuseCollab dock on the right:
   - **Project Creator:** Go to **⚙ Setup** → enter your username & project name → click **Register & Create Project** → copy the **Invite Code** (e.g. `BACH7X2K`) and share it with your collaborators!
   - **Collaborators:** Go to **⚙ Setup** → click **🔑 Join by Code** → enter your name (e.g. "Alice"), a username, password, and paste the **Invite Code** → click **Register & Join**.
3. The official cloud server (`https://musescore-collab.onrender.com`) is already pre-configured — no server setup needed!
