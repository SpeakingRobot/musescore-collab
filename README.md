# 🎵 MuseCollab

> **Git-style version control, measure-level cherry-picking, and live collaborative sessions for MuseScore.**

Works with **MuseScore 4** and **MuseScore 3** on **Windows** and **macOS**.  
Pre-configured with our official cloud server at `https://musescore-collab.onrender.com`.

---

## ⚡ 1-Click Installation

Anyone can install MuseCollab in 5 seconds without manual copy-pasting:

### 🪟 Windows
1. Download or clone this repository.
2. Double-click **`install.bat`**.
3. Done! It automatically detects your MuseScore folder, creates it if missing, and installs the plugin.

### 🍎 macOS
1. Download or clone this repository.
2. Double-click **`install.command`** in Finder (or run `./install.sh`).
3. Done! It installs directly into your Mac's MuseScore plugins directory.

### 💻 Or via Node.js / NPM (Any OS)
```bash
npm install
# or
npm run install-plugin
```

---

## 🚀 Activating in MuseScore

1. Open **MuseScore**.
2. Go to: **Plugins → Manage Plugins** (or **Preferences → Plugins** on Mac).
3. Find **MuseCollab** and tick the checkbox **[✓]**.
4. Open the plugin from the top menu: **Plugins → MuseCollab**.  
   *(It opens as a convenient dock on the right side of your sheet music).*

---

## 👥 How to Collaborate

### 1. Main Person (Creating a Project)
1. Open MuseCollab and click the **⚙ Setup** tab.
2. The server URL (`https://musescore-collab.onrender.com`) is **already pre-filled**!
3. Choose a username, password, and give your music project a name (e.g. `Symphony No 1`).
4. Click **Register & Create Project**.
5. You'll receive a short **Invite Code** (e.g. `BACH7X2K`). Send this code to your collaborators on WhatsApp, Discord, or Email!
6. Click **📤 Push** whenever you want to save your score to the `main` branch.

### 2. Collaborators (Joining with the Code)
1. Install the plugin using the 1-click installer above and open MuseScore.
2. Open MuseCollab and switch to the **🔑 Join by Code** tab.
3. Fill in:
   - **Your Name:** (e.g. `Rahul` or `Alice` — this is what the project creator sees)
   - A username and password
   - **Invite Code:** paste the code you received (e.g. `BACH7X2K`)
4. Click **Register & Join**.
5. You're in! You get your own dedicated branch (e.g. `rahul/main`) so your edits will never overwrite anyone else's music.
6. Make edits to your score and click **📤 Push** when ready.

---

## 🌟 Key Features

### 📐 Measure Cherry-Picking (Importing Selected Bars)
1. As the project creator, open the **🌿 Collab** tab to see all your collaborators and when they last pushed.
2. Click **[Measure Diff]** next to any collaborator.
3. The **📐 Bars** tab opens showing a breakdown of only the bars they changed or added (e.g. `Measure 4: C4 D4 → D4 F4`).
4. Check the boxes for the bars you want to keep.
5. Click **🎵 Import Selected Bar(s)** — only those chosen bars land in your score!

### 🔴 Real-Time Live Sessions
- **Broadcast Live:** Click **🔴 Go Live** to broadcast your sheet music changes in real-time.
- **Watch Live:** Click **[Watch Live]** next to any collaborator who is broadcasting to see their music live as they compose.
- **Edit Suggestions:** Watchers can submit suggestions (e.g. `Bar 4: C4 → D4`). The host gets instant **[Accept]** and **[Reject]** buttons.

### 🔄 Auto-Connect & Resume
- The plugin remembers your login for 30 days.
- When you open MuseScore tomorrow or next week, it automatically re-connects you to your music project with zero friction.

---

<details>
<summary>🛠️ Self-Hosting / Server Development (Optional)</summary>

You do **not** need to host anything to use MuseCollab — the cloud server is already running!  
If you want to run your own custom backend server instead:
- See [`server/RENDER_DEPLOY.md`](server/RENDER_DEPLOY.md) for Render + Neon PostgreSQL deployment instructions.
- Or run locally: `start-server.bat` (Windows) / `./start-server.sh` (Mac/Linux).
</details>

---

## License

MIT © [SpeakingRobot](https://github.com/SpeakingRobot)
