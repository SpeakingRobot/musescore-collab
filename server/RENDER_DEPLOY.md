# Deploying MuseCollab Server to Render + Neon (100% Free Forever)

This setup uses:
- **Neon** (`neon.tech`): Free cloud PostgreSQL database (0.5 GB storage, permanent, no credit card required)
- **Render** (`render.com`): Free Node.js web service (runs your Express + WebSocket API)

---

## Step 1: Create Free PostgreSQL Database on Neon (2 minutes)

1. Go to [https://neon.tech](https://neon.tech) and sign up with GitHub or Google (Free, no credit card).
2. Click **Create Project**.
3. Name your project: `musescore-collab`
4. Choose the region closest to you (e.g. `Singapore` or `Frankfurt`).
5. After creation, Neon displays your **Connection String**.
   It looks like:
   ```
   postgresql://username:password@ep-cool-flower-123456.ap-southeast-1.aws.neon.tech/neondb?sslmode=require
   ```
6. Copy this connection string. You'll paste it into Render.

---

## Step 2: Deploy to Render (3 minutes)

### Option A: Via GitHub (Recommended)

1. Push your `musescore-collab` project (or just the `server` folder) to a GitHub repository (can be private or public).
2. Go to [https://render.com](https://render.com) and log in.
3. Click **New +** → **Web Service**.
4. Connect your GitHub repository.
5. Configure the service:
   - **Name:** `musescore-collab` (or any name you like)
   - **Root Directory:** `server` (if your repo has `server/` and `plugin/`)
   - **Runtime:** `Node`
   - **Build Command:** `npm install`
   - **Start Command:** `node index.js`
   - **Instance Type:** `Free`
6. Scroll down to **Environment Variables** and add:
   - `DATABASE_URL`: *(Paste your Neon connection string from Step 1)*
   - `JWT_SECRET`: *(Enter any long random string e.g. `musescore_secret_key_998877`)*
   - `NODE_ENV`: `production`
7. Click **Deploy Web Service**.

Render will build and start your server in ~2 minutes!

---

## Step 3: Test Your Deployed Server

Once Render shows **Live**, copy your public URL (e.g. `https://musescore-collab.onrender.com`).

Test in your browser or terminal:
```bash
curl https://musescore-collab.onrender.com/health
```
Response:
```json
{
  "status": "ok",
  "version": "2.0.0",
  "time": "2026-10-23T..."
}
```

---

## Step 4: Paste Server URL into MuseScore Plugin

1. Open MuseScore.
2. In the **MuseCollab** plugin dock, open the **⚙ Settings** tab.
3. Paste your Render URL:
   `https://musescore-collab.onrender.com`
4. Register or create a project!

---

## Note on Render Free Tier Sleep Behavior
- Render free instances spin down after 15 minutes of inactivity.
- When someone opens MuseScore or sends a request, Render automatically wakes up in ~30–45 seconds.
- Your database is on Neon, so **no data or scores will ever be lost** when Render sleeps!
