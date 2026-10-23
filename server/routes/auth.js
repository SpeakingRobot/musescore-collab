'use strict';

/**
 * routes/auth.js
 *
 * Authentication routes + authenticateToken middleware.
 */

const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../utils/db');

const router = express.Router();

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-in-prod';
const JWT_EXPIRES_IN = '30d';

// ─── Middleware ───────────────────────────────────────────────────────────────

/**
 * Verifies the Bearer token from the Authorization header.
 * Sets req.user = { userId, username } on success.
 */
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Missing or invalid Authorization header' });
  }
  const token = authHeader.slice(7);
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.user = { userId: payload.userId, username: payload.username };
    next();
  } catch (err) {
    return res.status(401).json({ success: false, error: 'Token invalid or expired' });
  }
}

// ─── Routes ──────────────────────────────────────────────────────────────────

function generateInviteCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const alnum = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 4; i++) code += letters[Math.floor(Math.random() * letters.length)];
  for (let i = 0; i < 4; i++) code += alnum[Math.floor(Math.random() * alnum.length)];
  return code;
}

/**
 * POST /create-project
 * Body: { displayName, projectName }
 * Frictionless: No passwords or unique username requirements!
 * Automatically creates user, project with invite code, main branch, and owner membership.
 */
router.post('/create-project', async (req, res) => {
  try {
    const displayName = (req.body.displayName || req.body.username || '').trim();
    const projectName = (req.body.projectName || req.body.name || '').trim();

    if (!displayName) {
      return res.status(400).json({ success: false, error: 'Your name is required.' });
    }
    if (!projectName) {
      return res.status(400).json({ success: false, error: 'Project name is required.' });
    }

    if (!process.env.DATABASE_URL) {
      return res.status(500).json({ success: false, error: 'Database is not connected.' });
    }

    const internalUsername = `${displayName.toLowerCase().replace(/[^a-z0-9]/g, '') || 'musician'}_${Math.random().toString(36).substring(2, 8)}`;
    const user = await db.createUser(internalUsername, '');

    const token = jwt.sign(
      { userId: user.id, username: displayName, displayName: displayName },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES_IN }
    );

    let inviteCode;
    for (let attempts = 0; attempts < 10; attempts++) {
      const candidate = generateInviteCode();
      const existing = await db.getProjectByInviteCode(candidate);
      if (!existing) { inviteCode = candidate; break; }
    }
    if (!inviteCode) inviteCode = generateInviteCode();

    const project = await db.createProject(projectName, user.id, inviteCode);
    const branch = await db.createBranch(project.id, 'main', null);
    await db.addProjectMember(project.id, user.id, 'owner', 'main', displayName);

    const resultData = {
      token,
      project: {
        id: project.id,
        name: project.name,
        inviteCode: project.invite_code,
      },
      branch: 'main',
      displayName: displayName,
      user: { id: user.id, username: displayName },
    };

    return res.status(201).json({
      success: true,
      token,
      ...resultData,
      data: resultData,
    });
  } catch (err) {
    console.error('POST /create-project error:', err);
    return res.status(500).json({ success: false, error: 'Failed to create project: ' + (err.message || err) });
  }
});

/**
 * POST /join-project
 * Body: { displayName, inviteCode }
 * Frictionless: No passwords!
 * Automatically creates user, personal branch `displayName/main`, forks from main, and joins project.
 */
router.post('/join-project', async (req, res) => {
  try {
    const displayName = (req.body.displayName || req.body.username || '').trim();
    const inviteCode = (req.body.inviteCode || req.body.code || '').trim().toUpperCase();

    if (!displayName) {
      return res.status(400).json({ success: false, error: 'Your name is required.' });
    }
    if (!inviteCode) {
      return res.status(400).json({ success: false, error: 'Invite code is required.' });
    }

    if (!process.env.DATABASE_URL) {
      return res.status(500).json({ success: false, error: 'Database is not connected.' });
    }

    const project = await db.getProjectByInviteCode(inviteCode);
    if (!project) {
      return res.status(404).json({ success: false, error: 'Project not found with code: ' + inviteCode });
    }

    const internalUsername = `${displayName.toLowerCase().replace(/[^a-z0-9]/g, '') || 'musician'}_${Math.random().toString(36).substring(2, 8)}`;
    const user = await db.createUser(internalUsername, '');

    const token = jwt.sign(
      { userId: user.id, username: displayName, displayName: displayName },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES_IN }
    );

    const safeName = displayName.replace(/[^a-zA-Z0-9_\-]/g, '_');
    let branchName = `${safeName}/main`;
    let branchIndex = 1;
    while (await db.getBranchByName(project.id, branchName)) {
      branchIndex++;
      branchName = `${safeName}-${branchIndex}/main`;
    }

    const branch = await db.createBranch(project.id, branchName, 'main');

    const mainBranch = await db.getBranchByName(project.id, 'main');
    if (mainBranch) {
      const latestMainCommit = await db.getLatestCommit(mainBranch.id);
      if (latestMainCommit) {
        await db.createCommit(
          branch.id,
          project.id,
          user.id,
          'Branch initialised from main',
          latestMainCommit.score_data
        );
      }
    }

    await db.addProjectMember(project.id, user.id, 'member', branchName, displayName);

    const resultData = {
      token,
      project: {
        id: project.id,
        name: project.name,
        inviteCode: project.invite_code,
      },
      branch: branchName,
      displayName: displayName,
      user: { id: user.id, username: displayName },
    };

    return res.status(200).json({
      success: true,
      token,
      ...resultData,
      data: resultData,
    });
  } catch (err) {
    console.error('POST /join-project error:', err);
    return res.status(500).json({ success: false, error: 'Failed to join project: ' + (err.message || err) });
  }
});

/**
 * POST /register
 * Body: { username, password }
 * Returns JWT + user info.
 */
router.post('/register', async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ success: false, error: 'username and password are required' });
    }
    if (username.length < 3 || username.length > 32) {
      return res.status(400).json({ success: false, error: 'username must be 3–32 characters' });
    }
    if (password.length < 6) {
      return res.status(400).json({ success: false, error: 'password must be at least 6 characters' });
    }

    const existing = await db.getUserByUsername(username);
    if (existing) {
      // If the password matches, allow transparent login so users aren't locked out if client retries
      const valid = await bcrypt.compare(password, existing.password_hash);
      if (valid) {
        const token = jwt.sign({ userId: existing.id, username: existing.username }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
        return res.status(200).json({
          success: true,
          token,
          userId: existing.id,
          username: existing.username,
          data: {
            token,
            user: { id: existing.id, username: existing.username, createdAt: existing.created_at },
          },
        });
      }
      return res.status(409).json({ success: false, error: 'Username already taken' });
    }

    if (!process.env.DATABASE_URL) {
      return res.status(500).json({
        success: false,
        error: 'DATABASE_URL is not set in Render environment variables. Please add your Neon connection string to Render.'
      });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const user = await db.createUser(username, passwordHash);

    const token = jwt.sign({ userId: user.id, username: user.username }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });

    return res.status(201).json({
      success: true,
      token,
      userId: user.id,
      username: user.username,
      data: {
        token,
        user: { id: user.id, username: user.username, createdAt: user.created_at },
      },
    });
  } catch (err) {
    console.error('POST /register error:', err);
    return res.status(500).json({ success: false, error: 'Registration failed' });
  }
});

/**
 * POST /login
 * Body: { username, password }
 * Returns JWT + user info.
 */
router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ success: false, error: 'username and password are required' });
    }

    const user = await db.getUserByUsername(username);
    if (!user) {
      return res.status(401).json({ success: false, error: 'Invalid username or password' });
    }

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return res.status(401).json({ success: false, error: 'Invalid username or password' });
    }

    const token = jwt.sign({ userId: user.id, username: user.username }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });

    return res.json({
      success: true,
      token,
      userId: user.id,
      username: user.username,
      data: {
        token,
        user: { id: user.id, username: user.username, createdAt: user.created_at },
      },
    });
  } catch (err) {
    console.error('POST /login error:', err);
    return res.status(500).json({ success: false, error: 'Login failed' });
  }
});

/**
 * GET /me
 * Auth required.
 * Returns current user info + all projects they belong to for plugin context restoration.
 */
router.get('/me', authenticateToken, async (req, res) => {
  try {
    const user = await db.getUserById(req.user.userId);
    if (!user) {
      return res.status(404).json({ success: false, error: 'User not found' });
    }

    const projects = await db.getProjectsWithMetaByUserId(req.user.userId);

    return res.json({
      success: true,
      data: {
        userId: user.id,
        username: user.username,
        createdAt: user.created_at,
        projects: projects.map(p => ({
          projectId: p.project_id,
          projectName: p.project_name,
          inviteCode: p.invite_code,
          myBranch: p.my_branch,
          displayName: p.display_name,
          role: p.role,
          lastActivity: p.last_activity || null,
        })),
      },
    });
  } catch (err) {
    console.error('GET /me error:', err);
    return res.status(500).json({ success: false, error: 'Failed to fetch user info' });
  }
});

/**
 * POST /join
 * Auth required.
 * Body: { inviteCode, displayName? }
 * Joins a project via invite code, auto-creates a personal branch.
 */
router.post('/join', authenticateToken, async (req, res) => {
  try {
    const { inviteCode, displayName } = req.body;
    if (!inviteCode) {
      return res.status(400).json({ success: false, error: 'inviteCode is required' });
    }

    const project = await db.getProjectByInviteCode(inviteCode.toUpperCase());
    if (!project) {
      return res.status(404).json({ success: false, error: 'Project not found for that invite code' });
    }

    // Check not already a member
    const existingMember = await db.getProjectMember(project.id, req.user.userId);
    if (existingMember) {
      return res.status(409).json({ success: false, error: 'You are already a member of this project' });
    }

    // Auto-create personal branch named `username/main` forked from main
    const branchName = `${req.user.username}/main`;
    const branch = await db.createBranch(project.id, branchName, 'main');

    // Copy latest commit from main branch so they start from current state
    const mainBranch = await db.getBranchByName(project.id, 'main');
    if (mainBranch) {
      const latestMainCommit = await db.getLatestCommit(mainBranch.id);
      if (latestMainCommit) {
        await db.createCommit(
          branch.id,
          project.id,
          req.user.userId,
          `Branch initialised from main`,
          latestMainCommit.score_data
        );
      }
    }

    // Determine display name: use provided value or fall back to username
    const chosenDisplayName = (displayName && displayName.trim()) ? displayName.trim() : req.user.username;

    // Add user to project members
    await db.addProjectMember(project.id, req.user.userId, 'member', branchName, chosenDisplayName);

    return res.status(201).json({
      success: true,
      data: {
        project: {
          id: project.id,
          name: project.name,
          inviteCode: project.invite_code,
        },
        branch: {
          id: branch.id,
          name: branch.name,
          createdFrom: branch.created_from,
        },
        displayName: chosenDisplayName,
        message: 'Joined successfully',
      },
    });
  } catch (err) {
    console.error('POST /join error:', err);
    return res.status(500).json({ success: false, error: 'Failed to join project' });
  }
});

module.exports = { router, authenticateToken };
