'use strict';

/**
 * routes/live.js
 *
 * Real-time collaboration via WebSocket + REST endpoints for live sessions.
 */

const express = require('express');
const { WebSocketServer, WebSocket } = require('ws');
const jwt = require('jsonwebtoken');
const db = require('../utils/db');
const { authenticateToken } = require('./auth');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-in-prod';

// In-memory active live sessions:
// sessionId -> { id, projectId, hostUserId, hostUsername, clients: Set<WebSocket>, hostWs: WebSocket|null, lastSnapshot: object|null }
const sessions = new Map();

/**
 * Broadcast JSON payload to all clients in a session, optionally excluding one socket.
 */
function broadcastToSession(sessionId, payload, excludeWs = null) {
  const session = sessions.get(sessionId);
  if (!session) return;
  const msg = JSON.stringify(payload);
  for (const client of session.clients) {
    if (client !== excludeWs && client.readyState === WebSocket.OPEN) {
      try {
        client.send(msg);
      } catch (err) {
        console.error('WebSocket send error:', err);
      }
    }
  }
}

// ─── REST Endpoints ───────────────────────────────────────────────────────────

/**
 * POST /api/live/start
 * Auth required.
 * Body: { projectId }
 */
router.post('/live/start', authenticateToken, async (req, res) => {
  try {
    const { projectId } = req.body;
    if (!projectId) {
      return res.status(400).json({ success: false, error: 'projectId is required' });
    }

    const member = await db.getProjectMember(projectId, req.user.userId);
    if (!member) {
      return res.status(403).json({ success: false, error: 'You are not a member of this project' });
    }

    // Create session in DB
    const liveRecord = await db.createLiveSession(projectId, req.user.userId);
    const sessionId = liveRecord.id;

    // Track in memory
    sessions.set(sessionId, {
      id: sessionId,
      projectId,
      hostUserId: req.user.userId,
      hostUsername: req.user.username,
      clients: new Set(),
      hostWs: null,
      lastSnapshot: null,
      startedAt: new Date(),
    });

    return res.status(201).json({
      success: true,
      data: {
        sessionId,
        projectId,
        hostUsername: req.user.username,
        message: 'Live session started',
      },
    });
  } catch (err) {
    console.error('POST /live/start error:', err);
    return res.status(500).json({ success: false, error: 'Failed to start live session' });
  }
});

/**
 * DELETE /api/live/:sessionId
 * Auth required.
 * Host or project owner can end session.
 */
router.delete('/live/:sessionId', authenticateToken, async (req, res) => {
  try {
    const { sessionId } = req.params;
    const session = sessions.get(sessionId);

    // End in DB
    await db.endLiveSession(sessionId);

    if (session) {
      // Notify all connected clients
      broadcastToSession(sessionId, {
        type: 'session_ended',
        message: 'The live session has been ended by the host',
      });

      // Close all sockets
      for (const client of session.clients) {
        try {
          client.close(1000, 'Session ended');
        } catch (_) {}
      }
      sessions.delete(sessionId);
    }

    return res.json({ success: true, message: 'Live session ended' });
  } catch (err) {
    console.error('DELETE /live/:sessionId error:', err);
    return res.status(500).json({ success: false, error: 'Failed to end live session' });
  }
});

/**
 * GET /api/live/active/:projectId
 * Auth required.
 * Returns active live sessions for a project.
 */
router.get('/live/active/:projectId', authenticateToken, async (req, res) => {
  try {
    const { projectId } = req.params;
    const active = [];

    for (const s of sessions.values()) {
      if (s.projectId === projectId) {
        active.push({
          sessionId: s.id,
          projectId: s.projectId,
          hostUsername: s.hostUsername,
          hostUserId: s.hostUserId,
          watcherCount: Math.max(0, s.clients.size - (s.hostWs ? 1 : 0)),
          hasSnapshot: !!s.lastSnapshot,
          startedAt: s.startedAt,
        });
      }
    }

    return res.json({ success: true, data: active });
  } catch (err) {
    console.error('GET /live/active error:', err);
    return res.status(500).json({ success: false, error: 'Failed to get active live sessions' });
  }
});

// ─── REST Polling Endpoints (Compatible with standard Qt/QML without QtWebSockets) ───

/**
 * POST /api/live/:sessionId/snapshot
 * Host broadcasts a score snapshot via HTTP.
 */
router.post('/live/:sessionId/snapshot', authenticateToken, async (req, res) => {
  try {
    const { sessionId } = req.params;
    const { scoreData } = req.body;
    const session = sessions.get(sessionId);

    if (!session) {
      return res.status(404).json({ success: false, error: 'Live session not found or ended' });
    }
    if (session.hostUserId !== req.user.userId) {
      return res.status(403).json({ success: false, error: 'Only the host can push snapshots' });
    }

    session.lastSnapshot = scoreData;
    session.lastSnapshotTime = new Date().toISOString();

    // Also broadcast to any connected WebSockets
    broadcastToSession(sessionId, {
      type: 'score_update',
      scoreData,
      from: req.user.username,
      timestamp: session.lastSnapshotTime,
    });

    return res.json({ success: true, timestamp: session.lastSnapshotTime });
  } catch (err) {
    console.error('POST /live/:sessionId/snapshot error:', err);
    return res.status(500).json({ success: false, error: 'Failed to update snapshot' });
  }
});

/**
 * GET /api/live/:sessionId/snapshot
 * Watcher polls for the latest score snapshot.
 */
router.get('/live/:sessionId/snapshot', authenticateToken, async (req, res) => {
  try {
    const { sessionId } = req.params;
    const session = sessions.get(sessionId);

    if (!session) {
      return res.status(404).json({ success: false, error: 'Live session not found or ended' });
    }

    return res.json({
      success: true,
      data: {
        sessionId,
        hostUsername: session.hostUsername,
        watcherCount: session.clients.size,
        lastSnapshot: session.lastSnapshot,
        lastSnapshotTime: session.lastSnapshotTime || null,
        suggestions: session.suggestions || [],
      },
    });
  } catch (err) {
    console.error('GET /live/:sessionId/snapshot error:', err);
    return res.status(500).json({ success: false, error: 'Failed to get snapshot' });
  }
});

/**
 * POST /api/live/:sessionId/suggest
 * Watcher sends an edit suggestion to the host.
 */
router.post('/live/:sessionId/suggest', authenticateToken, async (req, res) => {
  try {
    const { sessionId } = req.params;
    const { measureNumber, fromNote, toNote, description } = req.body;
    const session = sessions.get(sessionId);

    if (!session) {
      return res.status(404).json({ success: false, error: 'Live session not found' });
    }

    if (!session.suggestions) session.suggestions = [];
    const suggestion = {
      id: Date.now().toString(),
      from: req.user.username,
      measureNumber: measureNumber || 1,
      fromNote: fromNote || '',
      toNote: toNote || '',
      description: description || `Measure ${measureNumber}: ${fromNote} → ${toNote}`,
      createdAt: new Date().toISOString(),
    };

    session.suggestions.push(suggestion);
    if (session.suggestions.length > 30) session.suggestions.shift();

    // Also forward to host via WebSocket if connected
    if (session.hostWs && session.hostWs.readyState === WebSocket.OPEN) {
      session.hostWs.send(JSON.stringify({ type: 'edit_suggestion', ...suggestion }));
    }

    return res.json({ success: true, data: suggestion });
  } catch (err) {
    console.error('POST /live/:sessionId/suggest error:', err);
    return res.status(500).json({ success: false, error: 'Failed to send suggestion' });
  }
});

// ─── WebSocket Server ─────────────────────────────────────────────────────────

function setupWebSocket(server) {
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (request, socket, head) => {
    try {
      const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`);
      const pathname = url.pathname; // e.g. /live-ws/:sessionId

      if (!pathname.startsWith('/live-ws/')) {
        socket.destroy();
        return;
      }

      const sessionId = pathname.replace('/live-ws/', '').trim();
      const token = url.searchParams.get('token');

      if (!token) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }

      let payload;
      try {
        payload = jwt.verify(token, JWT_SECRET);
      } catch (e) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }

      const session = sessions.get(sessionId);
      if (!session) {
        socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
        socket.destroy();
        return;
      }

      const isHost = (payload.userId === session.hostUserId);

      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request, {
          sessionId,
          userId: payload.userId,
          username: payload.username,
          isHost,
          session,
        });
      });
    } catch (err) {
      console.error('WebSocket upgrade error:', err);
      socket.destroy();
    }
  });

  wss.on('connection', (ws, req, meta) => {
    const { sessionId, userId, username, isHost, session } = meta;

    session.clients.add(ws);
    if (isHost) {
      session.hostWs = ws;
    }

    const watcherCount = Math.max(0, session.clients.size - (session.hostWs ? 1 : 0));

    // Send welcome / initial state
    ws.send(JSON.stringify({
      type: 'connected',
      sessionId,
      isHost,
      hostUsername: session.hostUsername,
      watcherCount,
      lastSnapshot: session.lastSnapshot,
    }));

    // Notify others that a peer joined
    broadcastToSession(sessionId, {
      type: 'peer_joined',
      username,
      isHost,
      watcherCount,
    }, ws);

    ws.on('message', (rawData) => {
      try {
        const msg = JSON.parse(rawData);

        if (msg.type === 'ping') {
          ws.send(JSON.stringify({ type: 'pong' }));
          return;
        }

        // Host broadcasting live score snapshot
        if (msg.type === 'score_snapshot' && isHost) {
          session.lastSnapshot = msg.scoreData;
          const currentWatchers = Math.max(0, session.clients.size - 1);
          broadcastToSession(sessionId, {
            type: 'score_update',
            scoreData: msg.scoreData,
            from: username,
            watcherCount: currentWatchers,
            timestamp: new Date().toISOString(),
          }, ws);
          return;
        }

        // Watcher suggesting an edit to the host
        if (msg.type === 'suggest_edit') {
          if (session.hostWs && session.hostWs.readyState === WebSocket.OPEN) {
            session.hostWs.send(JSON.stringify({
              type: 'edit_suggestion',
              from: username,
              measureNumber: msg.measureNumber,
              fromNote: msg.fromNote,
              toNote: msg.toNote,
              description: msg.description || `Measure ${msg.measureNumber}: ${msg.fromNote} → ${msg.toNote}`,
              timestamp: new Date().toISOString(),
            }));
          }
          return;
        }

        // Host accepting or rejecting suggestion (notify watcher)
        if (msg.type === 'suggestion_response' && isHost) {
          broadcastToSession(sessionId, {
            type: 'suggestion_result',
            targetUser: msg.targetUser,
            accepted: !!msg.accepted,
            measureNumber: msg.measureNumber,
          });
          return;
        }
      } catch (err) {
        console.error('WebSocket message parsing error:', err);
      }
    });

    ws.on('close', () => {
      session.clients.delete(ws);
      if (ws === session.hostWs) {
        session.hostWs = null;
      }
      const currentWatchers = Math.max(0, session.clients.size - (session.hostWs ? 1 : 0));
      broadcastToSession(sessionId, {
        type: 'peer_left',
        username,
        isHost,
        watcherCount: currentWatchers,
      });
    });

    ws.on('error', (err) => {
      console.error(`WebSocket error for ${username}:`, err);
    });
  });

  return wss;
}

module.exports = {
  router,
  setupWebSocket,
  sessions,
};
