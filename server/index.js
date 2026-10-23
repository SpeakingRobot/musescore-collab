'use strict';

require('dotenv').config();

const express = require('express');
const http    = require('http');
const cors    = require('cors');
const morgan  = require('morgan');

const { initDb }            = require('./utils/db');
const { router: authRouter } = require('./routes/auth');
const scoresRouter          = require('./routes/scores');
const { router: liveRouter, setupWebSocket } = require('./routes/live');

// ─── Bootstrap DB ──────────────────────────────────────────────────────────────

(async () => {
  try {
    await initDb();
    console.log('✅  PostgreSQL database initialised.');
  } catch (err) {
    console.error('❌  Failed to initialise database:', err.message || err);
    // Continue running even if DB init fails initially (e.g. invalid connection in dev)
  }
})();

// ─── App setup ─────────────────────────────────────────────────────────────────

const app = express();

app.use(cors());
app.use(morgan('dev'));
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// ─── Health & info routes ──────────────────────────────────────────────────────

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    version: '2.0.0',
    time: new Date().toISOString(),
  });
});

app.get('/', (_req, res) => {
  res.json({
    name: 'MuseCollab API',
    version: '2.0.0',
    description: 'Collaborative version control and live session server for MuseScore.',
    endpoints: {
      auth: {
        register: 'POST /api/auth/register',
        login:    'POST /api/auth/login',
        me:       'GET /api/auth/me',
        join:     'POST /api/auth/join (join with inviteCode + displayName)',
      },
      projects: {
        create:         'POST /api/projects',
        list:           'GET /api/projects',
        get:            'GET /api/projects/:projectId',
        branches:       'GET /api/projects/:projectId/branches',
        createBranch:   'POST /api/projects/:projectId/branches',
        push:           'POST /api/projects/:projectId/branches/:branchName/push',
        pull:           'GET /api/projects/:projectId/branches/:branchName/pull',
        history:        'GET /api/projects/:projectId/branches/:branchName/history',
        collaborators:  'GET /api/projects/:projectId/collaborators',
        measuresDiff:   'GET /api/projects/:projectId/measures?branch=...&against=...',
        importMeasures: 'POST /api/projects/:projectId/import-measures',
        merge:          'POST /api/projects/:projectId/merge',
      },
      live: {
        start:  'POST /api/live/start',
        end:    'DELETE /api/live/:sessionId',
        active: 'GET /api/live/active/:projectId',
        ws:     'ws://host/live-ws/:sessionId?token=JWT',
      },
    },
  });
});

// ─── Mount routers ─────────────────────────────────────────────────────────────

app.use('/api/auth', authRouter);
app.use('/api',      scoresRouter);
app.use('/api',      liveRouter);

// ─── 404 handler ──────────────────────────────────────────────────────────────

app.use((_req, res) => {
  res.status(404).json({ success: false, error: 'Route not found' });
});

// ─── Global error handler ─────────────────────────────────────────────────────

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error('[Unhandled error]', err);
  res.status(500).json({
    success: false,
    error: process.env.NODE_ENV === 'production'
      ? 'An unexpected error occurred'
      : err.message || 'An unexpected error occurred',
  });
});

// ─── Start HTTP & WebSocket server ────────────────────────────────────────────

const server = http.createServer(app);
setupWebSocket(server);

const PORT = Number(process.env.PORT) || 3001;

server.listen(PORT, () => {
  console.log(`🎵  MuseCollab v2 running on port ${PORT}`);
});

module.exports = app;
