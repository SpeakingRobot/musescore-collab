'use strict';

/**
 * routes/scores.js
 *
 * Project, branch, commit, and collaboration endpoints.
 */

const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { authenticateToken } = require('./auth');
const db = require('../utils/db');
const { diffScores, mergeDiffs, getMeasureDiff, importMeasures } = require('../utils/mscxDiff');

const router = express.Router();

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Generate a random invite code: 4 uppercase letters + 4 alphanumeric chars.
 * Example: "BACH7X2K"
 */
function generateInviteCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I/O to avoid confusion
  const alnum = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 4; i++) code += letters[Math.floor(Math.random() * letters.length)];
  for (let i = 0; i < 4; i++) code += alnum[Math.floor(Math.random() * alnum.length)];
  return code;
}

/**
 * Checks that req.user is a member of the given project.
 * Returns the project object on success, or sends 403/404 and returns null.
 */
async function requireMember(req, res, projectId) {
  const project = await db.getProjectById(projectId);
  if (!project) {
    res.status(404).json({ success: false, error: 'Project not found' });
    return null;
  }
  const member = await db.getProjectMember(projectId, req.user.userId);
  if (!member) {
    res.status(403).json({ success: false, error: 'You are not a member of this project' });
    return null;
  }
  return project;
}

/**
 * Checks that req.user is the OWNER of the given project.
 * Returns { project, member } on success, or sends 403/404 and returns null.
 */
async function requireOwner(req, res, projectId) {
  const project = await db.getProjectById(projectId);
  if (!project) {
    res.status(404).json({ success: false, error: 'Project not found' });
    return null;
  }
  const member = await db.getProjectMember(projectId, req.user.userId);
  if (!member || member.role !== 'owner') {
    res.status(403).json({ success: false, error: 'Only the project owner can perform this action' });
    return null;
  }
  return { project, member };
}

// ─── /me/projects ─────────────────────────────────────────────────────────────

/**
 * GET /api/me/projects
 * Auth required.
 * Returns all projects the user is a member of, with branch + displayName context.
 * Used by the plugin on startup to auto-restore context.
 */
router.get('/me/projects', authenticateToken, async (req, res) => {
  try {
    const projects = await db.getProjectsWithMetaByUserId(req.user.userId);
    return res.json({
      success: true,
      data: projects.map(p => ({
        projectId: p.project_id,
        projectName: p.project_name,
        inviteCode: p.invite_code,
        myBranch: p.my_branch,
        displayName: p.display_name,
        role: p.role,
        lastActivity: p.last_activity || null,
      })),
    });
  } catch (err) {
    console.error('GET /me/projects error:', err);
    return res.status(500).json({ success: false, error: 'Failed to fetch projects' });
  }
});

// ─── Projects ─────────────────────────────────────────────────────────────────

/**
 * POST /api/projects
 * Auth required.
 * Body: { name }
 * Creates a new project, initialises a 'main' branch, adds creator as owner.
 */
router.post('/projects', authenticateToken, async (req, res) => {
  try {
    const { name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ success: false, error: 'Project name is required' });
    }

    // Generate a unique invite code (retry on collision)
    let inviteCode;
    let attempts = 0;
    while (attempts < 5) {
      const candidate = generateInviteCode();
      const exists = await db.getProjectByInviteCode(candidate);
      if (!exists) { inviteCode = candidate; break; }
      attempts++;
    }
    if (!inviteCode) {
      return res.status(500).json({ success: false, error: 'Could not generate unique invite code' });
    }

    const project = await db.createProject(name.trim(), req.user.userId, inviteCode);
    const branch = await db.createBranch(project.id, 'main', null);

    // Owner display name defaults to their username
    await db.addProjectMember(project.id, req.user.userId, 'owner', 'main', req.user.username);

    return res.status(201).json({
      success: true,
      data: {
        project: {
          id: project.id,
          name: project.name,
          inviteCode: project.invite_code,
          createdAt: project.created_at,
        },
        branch: {
          id: branch.id,
          name: branch.name,
          createdAt: branch.created_at,
        },
      },
    });
  } catch (err) {
    console.error('POST /projects error:', err);
    return res.status(500).json({ success: false, error: 'Failed to create project' });
  }
});

/**
 * GET /api/projects
 * Auth required.
 * Lists all projects the user is a member of.
 */
router.get('/projects', authenticateToken, async (req, res) => {
  try {
    const projects = await db.getProjectsByUserId(req.user.userId);
    return res.json({
      success: true,
      data: projects.map(p => ({
        id: p.id,
        name: p.name,
        inviteCode: p.invite_code,
        role: p.role,
        createdAt: p.created_at,
      })),
    });
  } catch (err) {
    console.error('GET /projects error:', err);
    return res.status(500).json({ success: false, error: 'Failed to list projects' });
  }
});

/**
 * GET /api/projects/:projectId
 * Auth required, member only.
 * Returns project details + invite code + member list + branch list.
 */
router.get('/projects/:projectId', authenticateToken, async (req, res) => {
  try {
    const project = await requireMember(req, res, req.params.projectId);
    if (!project) return;

    const [members, branches] = await Promise.all([
      db.getProjectMembers(project.id),
      db.getBranchesByProject(project.id),
    ]);

    return res.json({
      success: true,
      data: {
        id: project.id,
        name: project.name,
        inviteCode: project.invite_code,
        createdAt: project.created_at,
        members: members.map(m => ({
          userId: m.user_id,
          username: m.username,
          displayName: m.display_name,
          role: m.role,
          branchName: m.branch_name,
        })),
        branches: branches.map(b => ({
          id: b.id,
          name: b.name,
          createdFrom: b.created_from,
          createdAt: b.created_at,
        })),
      },
    });
  } catch (err) {
    console.error('GET /projects/:projectId error:', err);
    return res.status(500).json({ success: false, error: 'Failed to fetch project' });
  }
});

// ─── Branches ─────────────────────────────────────────────────────────────────

/**
 * GET /api/projects/:projectId/branches
 * Auth required, member.
 * Lists branches with their latest commit info.
 */
router.get('/projects/:projectId/branches', authenticateToken, async (req, res) => {
  try {
    const project = await requireMember(req, res, req.params.projectId);
    if (!project) return;

    const branches = await db.getBranchesByProject(project.id);
    const branchesWithCommit = await Promise.all(
      branches.map(async (b) => {
        const latest = await db.getLatestCommit(b.id);
        return {
          id: b.id,
          name: b.name,
          createdFrom: b.created_from,
          createdAt: b.created_at,
          latestCommit: latest
            ? { id: latest.id, message: latest.message, createdAt: latest.created_at, authorId: latest.author_id }
            : null,
        };
      })
    );

    return res.json({ success: true, data: branchesWithCommit });
  } catch (err) {
    console.error('GET /projects/:projectId/branches error:', err);
    return res.status(500).json({ success: false, error: 'Failed to list branches' });
  }
});

/**
 * POST /api/projects/:projectId/branches
 * Auth required, member.
 * Body: { name, fromBranch }
 * Creates a new branch forked from fromBranch.
 */
router.post('/projects/:projectId/branches', authenticateToken, async (req, res) => {
  try {
    const project = await requireMember(req, res, req.params.projectId);
    if (!project) return;

    const { name, fromBranch } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ success: false, error: 'Branch name is required' });
    }

    // Ensure branch doesn't already exist
    const existing = await db.getBranchByName(project.id, name.trim());
    if (existing) {
      return res.status(409).json({ success: false, error: 'Branch already exists' });
    }

    const branch = await db.createBranch(project.id, name.trim(), fromBranch || null);

    // If fromBranch is specified, copy its latest commit as seed
    if (fromBranch) {
      const srcBranch = await db.getBranchByName(project.id, fromBranch);
      if (srcBranch) {
        const latestCommit = await db.getLatestCommit(srcBranch.id);
        if (latestCommit) {
          await db.createCommit(
            branch.id,
            project.id,
            req.user.userId,
            `Branch initialised from ${fromBranch}`,
            latestCommit.score_data
          );
        }
      }
    }

    return res.status(201).json({
      success: true,
      data: {
        id: branch.id,
        name: branch.name,
        projectId: branch.project_id,
        createdFrom: branch.created_from,
        createdAt: branch.created_at,
      },
    });
  } catch (err) {
    console.error('POST /projects/:projectId/branches error:', err);
    return res.status(500).json({ success: false, error: 'Failed to create branch' });
  }
});

// ─── Push / Pull / History ────────────────────────────────────────────────────

/**
 * Helper to resolve the branch name from query, body, or path params.
 * Handles subpaths like "Rahul/main/commits" or "Rahul/main/head" or "Rahul/main/pull".
 */
function resolveBranch(req, explicitBranch = null) {
  if (explicitBranch) return explicitBranch.replace(/^\/+|\/+$/g, '').trim();
  let branch = req.query.branch || (req.body && req.body.branch) || req.params.branchName || null;
  if (branch) {
    try { branch = decodeURIComponent(branch); } catch (_) {}
    return branch.replace(/^\/+|\/+$/g, '').trim();
  }
  if (req.params[0]) {
    let rest = req.params[0];
    try { rest = decodeURIComponent(rest); } catch (_) {}
    const suffixes = ['/push', '/commits', '/pull', '/head', '/history'];
    for (const suffix of suffixes) {
      if (rest.endsWith(suffix)) {
        rest = rest.slice(0, -suffix.length);
        break;
      }
    }
    return rest.replace(/^\/+|\/+$/g, '').trim();
  }
  return 'main';
}

/**
 * Push handler: accepts both scoreData and content, JSON object or string.
 */
async function handlePush(req, res, explicitBranch = null) {
  try {
    const project = await requireMember(req, res, req.params.projectId);
    if (!project) return;

    let { scoreData, content, message } = req.body || {};
    let dataToSave = scoreData || content;

    if (!dataToSave) {
      return res.status(400).json({ success: false, error: 'scoreData or content is required' });
    }
    if (typeof dataToSave === 'string') {
      try {
        dataToSave = JSON.parse(dataToSave);
      } catch (_) {
        dataToSave = { raw: dataToSave };
      }
    }

    const commitMessage = (message && message.trim()) ? message.trim() : 'Update score';
    const branchName = resolveBranch(req, explicitBranch);

    let branch = await db.getBranchByName(project.id, branchName);
    if (!branch) {
      // Auto-create personal/feature branch if not yet in database
      branch = await db.createBranch(project.id, branchName, 'main');
    }

    const commit = await db.createCommit(
      branch.id,
      project.id,
      req.user.userId,
      commitMessage,
      dataToSave
    );

    return res.status(201).json({
      success: true,
      commitId: commit.id,
      data: {
        commitId: commit.id,
        branchId: commit.branch_id,
        branchName: branch.name,
        message: commit.message,
        createdAt: commit.created_at,
        authorId: commit.author_id,
      },
    });
  } catch (err) {
    console.error('Push error:', err);
    return res.status(500).json({ success: false, error: 'Failed to push commit: ' + err.message });
  }
}

/**
 * Pull handler: returns full score data for both scoreData and content fields.
 */
async function handlePull(req, res, explicitBranch = null) {
  try {
    const project = await requireMember(req, res, req.params.projectId);
    if (!project) return;

    const branchName = resolveBranch(req, explicitBranch);
    const branch = await db.getBranchByName(project.id, branchName);
    if (!branch) {
      return res.json({
        success: true,
        data: null,
        content: null,
        scoreData: null,
        message: `Branch '${branchName}' does not exist yet`,
      });
    }

    const commit = await db.getLatestCommit(branch.id);
    if (!commit) {
      return res.json({
        success: true,
        data: null,
        content: null,
        scoreData: null,
        message: 'No commits on this branch yet',
      });
    }

    const rawScore = commit.score_data;
    const scorePayload = (rawScore && rawScore.raw) ? rawScore.raw : rawScore;

    return res.json({
      success: true,
      commitId: commit.id,
      content: scorePayload,
      scoreData: scorePayload,
      message: commit.message,
      author: commit.author_id,
      data: {
        commitId: commit.id,
        branchId: commit.branch_id,
        branchName: branch.name,
        message: commit.message,
        authorId: commit.author_id,
        scoreData: scorePayload,
        content: scorePayload,
        createdAt: commit.created_at,
      },
    });
  } catch (err) {
    console.error('Pull error:', err);
    return res.status(500).json({ success: false, error: 'Failed to pull latest commit: ' + err.message });
  }
}

/**
 * History handler: returns commit list.
 */
async function handleHistory(req, res, explicitBranch = null) {
  try {
    const project = await requireMember(req, res, req.params.projectId);
    if (!project) return;

    const branchName = resolveBranch(req, explicitBranch);
    const branch = await db.getBranchByName(project.id, branchName);
    if (!branch) {
      return res.json({ success: true, data: [] });
    }

    const commits = await db.getCommitsByBranch(branch.id, 20);
    return res.json({
      success: true,
      data: commits.map(c => ({
        commitId: c.id,
        message: c.message,
        authorId: c.author_id,
        createdAt: c.created_at,
      })),
    });
  } catch (err) {
    console.error('History error:', err);
    return res.status(500).json({ success: false, error: 'Failed to fetch commit history: ' + err.message });
  }
}

// ─── Register Push / Pull / History Routes ────────────────────────────────────

// Direct endpoints with query param fallback (?branch=...)
router.post('/projects/:projectId/push', authenticateToken, (req, res) => handlePush(req, res));
router.post('/projects/:projectId/commits', authenticateToken, (req, res) => handlePush(req, res));
router.get('/projects/:projectId/pull', authenticateToken, (req, res) => handlePull(req, res));
router.get('/projects/:projectId/head', authenticateToken, (req, res) => handlePull(req, res));
router.get('/projects/:projectId/history', authenticateToken, (req, res) => handleHistory(req, res));

// Standard single-segment branch routes (e.g. /branches/main/push)
router.post('/projects/:projectId/branches/:branchName/push', authenticateToken, (req, res) => handlePush(req, res));
router.post('/projects/:projectId/branches/:branchName/commits', authenticateToken, (req, res) => handlePush(req, res));
router.get('/projects/:projectId/branches/:branchName/pull', authenticateToken, (req, res) => handlePull(req, res));
router.get('/projects/:projectId/branches/:branchName/head', authenticateToken, (req, res) => handlePull(req, res));
router.get('/projects/:projectId/branches/:branchName/history', authenticateToken, (req, res) => handleHistory(req, res));

// Wildcard routes for multi-segment branches (e.g. /branches/Rahul/main/pull, /branches/Rahul/main/commits)
router.post('/projects/:projectId/branches/*', authenticateToken, (req, res, next) => {
  const rest = req.params[0] || '';
  if (rest.endsWith('/push') || rest.endsWith('/commits')) {
    return handlePush(req, res);
  }
  next();
});

router.get('/projects/:projectId/branches/*', authenticateToken, (req, res, next) => {
  const rest = req.params[0] || '';
  if (rest.endsWith('/pull') || rest.endsWith('/head')) {
    return handlePull(req, res);
  }
  if (rest.endsWith('/history')) {
    return handleHistory(req, res);
  }
  return handlePull(req, res);
});

// ─── Collaborators ────────────────────────────────────────────────────────────

/**
 * GET /api/projects/:projectId/collaborators
 * Auth required, member.
 * Returns all members with branch name, last push time, and live status.
 */
router.get('/projects/:projectId/collaborators', authenticateToken, async (req, res) => {
  try {
    const project = await requireMember(req, res, req.params.projectId);
    if (!project) return;

    const [members, activeSessions] = await Promise.all([
      db.getProjectMembers(project.id),
      db.getActiveLiveSessionsByProject(project.id),
    ]);

    const liveUserIds = new Set(activeSessions.map(s => s.host_user_id));

    const collaborators = await Promise.all(
      members.map(async (m) => {
        const branch = await db.getBranchByName(project.id, m.branch_name);
        let lastPushAt = null;
        if (branch) {
          const latestCommit = await db.getLatestCommit(branch.id);
          lastPushAt = latestCommit ? latestCommit.created_at : null;
        }
        return {
          userId: m.user_id,
          username: m.username,
          displayName: m.display_name,
          role: m.role,
          branchName: m.branch_name,
          lastPushAt,
          isLive: liveUserIds.has(m.user_id),
        };
      })
    );

    return res.json({ success: true, data: collaborators });
  } catch (err) {
    console.error('GET /collaborators error:', err);
    return res.status(500).json({ success: false, error: 'Failed to fetch collaborators' });
  }
});

// ─── Invite ───────────────────────────────────────────────────────────────────

/**
 * POST /api/projects/:projectId/invite
 * Auth required, owner only.
 * Body: { username }
 * Invites an already-registered user by username.
 */
router.post('/projects/:projectId/invite', authenticateToken, async (req, res) => {
  try {
    const result = await requireOwner(req, res, req.params.projectId);
    if (!result) return;
    const { project } = result;

    const { username } = req.body;
    if (!username) {
      return res.status(400).json({ success: false, error: 'username is required' });
    }

    const invitee = await db.getUserByUsername(username);
    if (!invitee) {
      return res.status(404).json({ success: false, error: 'User not found' });
    }

    const alreadyMember = await db.getProjectMember(project.id, invitee.id);
    if (alreadyMember) {
      return res.status(409).json({ success: false, error: 'User is already a member of this project' });
    }

    const branchName = `${invitee.username}/main`;
    const branch = await db.createBranch(project.id, branchName, 'main');

    // Seed branch from main
    const mainBranch = await db.getBranchByName(project.id, 'main');
    if (mainBranch) {
      const latestMainCommit = await db.getLatestCommit(mainBranch.id);
      if (latestMainCommit) {
        await db.createCommit(
          branch.id,
          project.id,
          invitee.id,
          `Branch initialised from main`,
          latestMainCommit.score_data
        );
      }
    }

    await db.addProjectMember(project.id, invitee.id, 'member', branchName, invitee.username);

    return res.status(201).json({
      success: true,
      data: {
        message: `${invitee.username} has been added to the project`,
        branch: { id: branch.id, name: branch.name },
      },
    });
  } catch (err) {
    console.error('POST /invite error:', err);
    return res.status(500).json({ success: false, error: 'Failed to invite user' });
  }
});

// ─── Measure diff ─────────────────────────────────────────────────────────────

/**
 * GET /api/projects/:projectId/measures?branch=alice/main&against=main
 * Auth required, member.
 * Returns measure-level diff between two branches.
 */
router.get('/projects/:projectId/measures', authenticateToken, async (req, res) => {
  try {
    const project = await requireMember(req, res, req.params.projectId);
    if (!project) return;

    let { branch: branchName, against: againstName } = req.query;
    if (!branchName) {
      return res.status(400).json({ success: false, error: 'branch query param is required' });
    }
    const targetAgainst = againstName || 'main';

    const [branchA, branchB] = await Promise.all([
      db.getBranchByName(project.id, targetAgainst),
      db.getBranchByName(project.id, branchName),
    ]);

    if (!branchA || !branchB) {
      return res.json({ success: true, data: [], message: 'One or both branches not found' });
    }

    const [commitA, commitB] = await Promise.all([
      db.getLatestCommit(branchA.id),
      db.getLatestCommit(branchB.id),
    ]);

    if (!commitA || !commitB) {
      return res.json({ success: true, data: [], message: 'One or both branches have no commits' });
    }

    let scoreDataA = commitA.score_data;
    if (scoreDataA && scoreDataA.raw) scoreDataA = scoreDataA.raw;
    let scoreDataB = commitB.score_data;
    if (scoreDataB && scoreDataB.raw) scoreDataB = scoreDataB.raw;

    const measureDiff = getMeasureDiff(scoreDataA, scoreDataB);

    return res.json({ success: true, data: measureDiff });
  } catch (err) {
    console.error('GET /measures error:', err);
    return res.status(500).json({ success: false, error: 'Failed to compute measure diff' });
  }
});

// ─── Import measures ──────────────────────────────────────────────────────────

/**
 * POST /api/projects/:projectId/import-measures
 * Auth required, owner only.
 * Body: { fromBranch, measureNumbers: [4, 8, 15], commitMessage }
 * Imports specific measures from fromBranch into main, creates new commit.
 */
router.post('/projects/:projectId/import-measures', authenticateToken, async (req, res) => {
  try {
    const result = await requireOwner(req, res, req.params.projectId);
    if (!result) return;
    const { project } = result;

    const { fromBranch, measureNumbers, commitMessage } = req.body;
    if (!fromBranch) {
      return res.status(400).json({ success: false, error: 'fromBranch is required' });
    }
    if (!Array.isArray(measureNumbers) || measureNumbers.length === 0) {
      return res.status(400).json({ success: false, error: 'measureNumbers must be a non-empty array' });
    }

    const [srcBranch, mainBranch] = await Promise.all([
      db.getBranchByName(project.id, fromBranch),
      db.getBranchByName(project.id, 'main'),
    ]);

    if (!srcBranch) return res.status(404).json({ success: false, error: `Branch '${fromBranch}' not found` });
    if (!mainBranch) return res.status(404).json({ success: false, error: 'main branch not found' });

    const [srcCommit, mainCommit] = await Promise.all([
      db.getLatestCommit(srcBranch.id),
      db.getLatestCommit(mainBranch.id),
    ]);

    if (!srcCommit) return res.status(400).json({ success: false, error: `Branch '${fromBranch}' has no commits` });

    let baseScore = mainCommit ? mainCommit.score_data : null;
    if (baseScore && baseScore.raw) baseScore = baseScore.raw;
    let srcScore = srcCommit.score_data;
    if (srcScore && srcScore.raw) srcScore = srcScore.raw;

    let mergedScore;
    if (!baseScore) {
      mergedScore = srcScore;
    } else {
      mergedScore = importMeasures(baseScore, srcScore, measureNumbers);
    }

    const message = (commitMessage && commitMessage.trim())
      ? commitMessage.trim()
      : `Import measures ${measureNumbers.join(', ')} from ${fromBranch}`;

    const newCommit = await db.createCommit(
      mainBranch.id,
      project.id,
      req.user.userId,
      message,
      mergedScore
    );

    return res.status(201).json({
      success: true,
      data: {
        commitId: newCommit.id,
        message: newCommit.message,
        createdAt: newCommit.created_at,
        importedMeasures: measureNumbers,
        fromBranch,
      },
    });
  } catch (err) {
    console.error('POST /import-measures error:', err);
    return res.status(500).json({ success: false, error: 'Failed to import measures' });
  }
});

// ─── Merge ────────────────────────────────────────────────────────────────────

/**
 * POST /api/projects/:projectId/merge
 * Auth required, member.
 * Body: { sourceBranch, targetBranch, acceptedDiffIndices: [] }
 * Selective merge: applies accepted diffs from source onto target, creates new commit.
 */
router.post('/projects/:projectId/merge', authenticateToken, async (req, res) => {
  try {
    const project = await requireMember(req, res, req.params.projectId);
    if (!project) return;

    const { sourceBranch, targetBranch, acceptedDiffIndices } = req.body;
    if (!sourceBranch || !targetBranch) {
      return res.status(400).json({ success: false, error: 'sourceBranch and targetBranch are required' });
    }
    if (!Array.isArray(acceptedDiffIndices)) {
      return res.status(400).json({ success: false, error: 'acceptedDiffIndices must be an array' });
    }

    const [srcBranch, tgtBranch] = await Promise.all([
      db.getBranchByName(project.id, sourceBranch),
      db.getBranchByName(project.id, targetBranch),
    ]);

    if (!srcBranch) return res.status(404).json({ success: false, error: `Source branch '${sourceBranch}' not found` });
    if (!tgtBranch) return res.status(404).json({ success: false, error: `Target branch '${targetBranch}' not found` });

    const [srcCommit, tgtCommit] = await Promise.all([
      db.getLatestCommit(srcBranch.id),
      db.getLatestCommit(tgtBranch.id),
    ]);

    if (!srcCommit) return res.status(400).json({ success: false, error: `Branch '${sourceBranch}' has no commits` });
    if (!tgtCommit) return res.status(400).json({ success: false, error: `Branch '${targetBranch}' has no commits` });

    const { diffs, summary } = diffScores(tgtCommit.score_data, srcCommit.score_data);

    if (acceptedDiffIndices.length === 0) {
      return res.json({
        success: true,
        data: { message: 'No diffs accepted — nothing merged', diffs, summary },
      });
    }

    const mergedScore = mergeDiffs(tgtCommit.score_data, srcCommit.score_data, acceptedDiffIndices);

    const newCommit = await db.createCommit(
      tgtBranch.id,
      project.id,
      req.user.userId,
      `Merge ${acceptedDiffIndices.length} change(s) from ${sourceBranch} into ${targetBranch}`,
      mergedScore
    );

    return res.status(201).json({
      success: true,
      data: {
        commitId: newCommit.id,
        message: newCommit.message,
        createdAt: newCommit.created_at,
        acceptedCount: acceptedDiffIndices.length,
        totalDiffs: diffs.length,
        summary,
      },
    });
  } catch (err) {
    console.error('POST /merge error:', err);
    return res.status(500).json({ success: false, error: 'Failed to merge branches' });
  }
});

module.exports = router;
