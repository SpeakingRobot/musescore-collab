# MuseCollab v2 — Collaborative Version Control & Live Collab for MuseScore

Git-style version control, measure-level cherry-picking, and real-time live sessions for MuseScore 3 and 4 on **Mac** and **Windows**.

---

## What's New in v2

- 🔑 **Invite Code System**: Create a project and get a short code (e.g. `BACH7X2K`). Collaborators just type the code to join.
- 🪪 **Display Names**: When collaborators join, they type their friendly name (e.g. "Rahul", "Alice"). The project owner sees exactly who wrote what.
- 📐 **Measure Cherry-Picking**: View collaborator branches measure-by-measure. Select only the bars you like and click **Import Selected** — only those bars land in your main score.
- 🔴 **Live Collaboration Sessions**: Broadcast your music score in real-time or watch a collaborator's score live with edit suggestions.
- 🔄 **Auto-Connect & Resume**: Next time you open MuseScore, the plugin automatically reconnects to your music project with a 30-day session token.
- ☁️ **100% Free Cloud Deployment**: Host the server for free on **Render** with **Neon PostgreSQL** — no credit cards needed, no data loss on restarts.

---

## Project Structure

```
musescore-collab/
├── plugin/                    ← Install this folder into MuseScore Plugins
│   ├── CollabPlugin.qml       ← Main dock panel (5 tabs: Setup, Collab, Bars, Live, Diff)
│   ├── ui/
│   │   ├── SettingsPanel.qml  ← Register, Create Project & Join with Invite Code
│   │   ├── BranchPanel.qml    ← Collaborators list, branch switcher & live controls
│   │   ├── MeasurePicker.qml  ← Cherry-pick & import specific bars
│   │   ├── LivePanel.qml      ← Real-time broadcast and watcher panel
│   │   └── DiffViewer.qml     ← Note-by-note color-coded diff viewer
│   └── js/
│       ├── api.js             ← Pure XMLHttpRequest network calls (Qt-compatible)
│       ├── mscxParser.js      ← MSCX XML parser & semantic score differ
│       └── scoreWriter.js     ← MuseScore cursor navigation & score writer
└── server/                    ← Node.js + PostgreSQL backend
    ├── index.js               ← Express + HTTP/WebSocket server
    ├── routes/
    │   ├── auth.js            ← Register, Login, Me, Join by invite code
    │   ├── scores.js          ← Projects, branches, commits, measure import
    │   └── live.js            ← Live sessions & real-time broadcast
    ├── utils/
    │   ├── db.js              ← PostgreSQL queries (Neon-ready)
    │   └── mscxDiff.js        ← Semantic measure & note diffing engine
    ├── render.yaml            ← 1-click Render blueprint deployment
    └── RENDER_DEPLOY.md       ← Step-by-step free deployment guide
```

---

## 🚀 Quick Setup (2 Steps)

### Step 1: Deploy or Run the Server

#### Option A: Free Cloud Deployment on Render + Neon (Recommended)
Follow the step-by-step instructions in [`server/RENDER_DEPLOY.md`](server/RENDER_DEPLOY.md):
1. Create a free PostgreSQL database on [Neon.tech](https://neon.tech) (Free, no credit card required).
2. Connect your repository to [Render.com](https://render.com) (Free Node.js Web Service).
3. Set `DATABASE_URL` to your Neon connection string.
4. Copy your live Render URL (e.g. `https://musescore-collab.onrender.com`).

#### Option B: Run Locally on Your PC or Mac
- **Mac / Linux**: Run `./start-server.sh`
- **Windows**: Double-click `start-server.bat`
- Server starts on `http://localhost:3001` (or your local Wi-Fi IP `http://192.168.x.x:3001`).

---

### Step 2: Install the Plugin in MuseScore

Copy the `plugin/` folder into your MuseScore Plugins folder:

| Operating System | Default MuseScore 4 Plugin Folder |
|---|---|
| **macOS** | `~/Documents/MuseScore4/Plugins/MuseCollab/` |
| **Windows** | `%USERPROFILE%\Documents\MuseScore4\Plugins\MuseCollab\` |

#### Mac Installation (Terminal):
```bash
mkdir -p ~/Documents/MuseScore4/Plugins/MuseCollab
cp -r /path/to/musescore-collab/plugin/. ~/Documents/MuseScore4/Plugins/MuseCollab/
```

#### Windows Installation (PowerShell):
```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\Documents\MuseScore4\Plugins\MuseCollab"
Copy-Item -Recurse plugin\* "$env:USERPROFILE\Documents\MuseScore4\Plugins\MuseCollab\"
```

#### Enable in MuseScore:
1. Open **MuseScore**.
2. Go to **Plugins → Manage Plugins** (or **Preferences → Plugins**).
3. Check the box next to **MuseCollab** to enable it.
4. Open it from the top menu: **Plugins → MuseCollab** (it docks on the right side).

---

## 👥 How to Collaborate

### 1. Main Person (Project Creator)
1. In the MuseCollab dock, go to **⚙ Setup**.
2. Enter your Server URL (e.g. your Render URL), create a username, password, and give your project a name (e.g. `Symphony No 1`).
3. Click **Register & Create Project**.
4. The plugin creates the project, generates an **Invite Code** (e.g. `BACH7X2K`), and switches to the **🌿 Collab** tab.
5. Share the invite code with your collaborators!
6. Click **📤 Push** anytime to push your current score to the `main` branch.

### 2. Collaborator (Joining with Code)
1. Open MuseScore and open the **MuseCollab** plugin.
2. Go to **⚙ Setup** and click the **🔑 Join by Code** tab.
3. Enter the Server URL, your username, password, **Your Name** (e.g. "Rahul"), and paste the **Invite Code** (`BACH7X2K`).
4. Click **Register & Join**.
5. The plugin auto-creates a dedicated branch (e.g. `rahul/main`) forked from the main score.
6. The collaborator works freely on their own score without affecting anyone else, and clicks **📤 Push** when ready.

### 3. Cherry-Picking Bars (Main Person)
1. The project owner sees all collaborators in the **🌿 Collab** panel showing their display names and last push times.
2. Click **[Measure Diff]** next to any collaborator.
3. The **📐 Bars** tab opens, showing a checklist of every modified or newly added measure with musical pitch summaries (e.g. `C4 D4 E4 → D4 F4 G4`).
4. Check the boxes for the measures you like.
5. Click **🎵 Import Selected Bar(s)**.
6. Only those selected bars are imported into your main score — everything else remains untouched!

### 4. Live Sessions
- **Broadcasting Live**: Click **🔴 Go Live** in the Collab tab. Watchers see updates live as you work, and you can review real-time edit suggestions.
- **Watching Live**: Click **[Watch Live]** next to any collaborator who is broadcasting to view their score in real time and suggest edits.

---

## Compatibility

- **MuseScore**: 4.x and 3.x
- **Platforms**: macOS (Apple Silicon & Intel), Windows 10/11, Linux
- **No Extra Dependencies**: Does not require external C++ libraries or `QtWebSockets` installation; runs directly inside MuseScore using native Qt Quick.
