'use strict';

/**
 * utils/db.js
 *
 * PostgreSQL database layer using the `pg` Pool.
 * Connects to Neon (or any Postgres) via DATABASE_URL.
 * All functions are async and return plain objects / arrays.
 */

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL && !process.env.DATABASE_URL.includes('localhost')
    ? { rejectUnauthorized: false }
    : false,
});

if (!process.env.DATABASE_URL) {
  console.warn('⚠️  DATABASE_URL environment variable is missing!');
}

// ─── Schema initialisation ──────────────────────────────────────────────────

async function initDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      username TEXT NOT NULL,
      password_hash TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key;
    ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

    CREATE TABLE IF NOT EXISTS projects (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      name TEXT NOT NULL,
      owner_id UUID REFERENCES users(id),
      invite_code TEXT UNIQUE NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS project_members (
      project_id UUID REFERENCES projects(id),
      user_id UUID REFERENCES users(id),
      role TEXT NOT NULL CHECK(role IN ('owner','member')),
      branch_name TEXT NOT NULL,
      display_name TEXT NOT NULL DEFAULT '',
      PRIMARY KEY (project_id, user_id)
    );

    CREATE TABLE IF NOT EXISTS branches (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id UUID REFERENCES projects(id),
      name TEXT NOT NULL,
      created_from TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(project_id, name)
    );

    CREATE TABLE IF NOT EXISTS commits (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      branch_id UUID REFERENCES branches(id),
      project_id UUID REFERENCES projects(id),
      author_id UUID REFERENCES users(id),
      message TEXT NOT NULL,
      score_data JSONB NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS live_sessions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id UUID REFERENCES projects(id),
      host_user_id UUID REFERENCES users(id),
      started_at TIMESTAMPTZ DEFAULT NOW(),
      ended_at TIMESTAMPTZ
    );
  `);
}

// ─── Users ──────────────────────────────────────────────────────────────────

async function getUserById(id) {
  const { rows } = await pool.query(
    'SELECT id, username, created_at FROM users WHERE id = $1',
    [id]
  );
  return rows[0] || null;
}

async function getUserByUsername(username) {
  const { rows } = await pool.query(
    'SELECT id, username, password_hash, created_at FROM users WHERE username = $1',
    [username]
  );
  return rows[0] || null;
}

async function createUser(username, passwordHash = '') {
  const { rows } = await pool.query(
    'INSERT INTO users (username, password_hash) VALUES ($1, $2) RETURNING id, username, created_at',
    [username, passwordHash || '']
  );
  return rows[0];
}

// ─── Projects ───────────────────────────────────────────────────────────────

async function getProjectById(id) {
  const { rows } = await pool.query(
    'SELECT id, name, owner_id, invite_code, created_at FROM projects WHERE id = $1',
    [id]
  );
  return rows[0] || null;
}

async function getProjectByName(name) {
  const { rows } = await pool.query(
    'SELECT id, name, owner_id, invite_code, created_at FROM projects WHERE name = $1',
    [name]
  );
  return rows[0] || null;
}

async function getProjectByInviteCode(code) {
  const { rows } = await pool.query(
    'SELECT id, name, owner_id, invite_code, created_at FROM projects WHERE invite_code = $1',
    [code]
  );
  return rows[0] || null;
}

async function createProject(name, ownerId, inviteCode) {
  const { rows } = await pool.query(
    'INSERT INTO projects (name, owner_id, invite_code) VALUES ($1, $2, $3) RETURNING id, name, owner_id, invite_code, created_at',
    [name, ownerId, inviteCode]
  );
  return rows[0];
}

async function getProjectsByUserId(userId) {
  const { rows } = await pool.query(
    `SELECT p.id, p.name, p.owner_id, p.invite_code, p.created_at, pm.role
     FROM projects p
     JOIN project_members pm ON pm.project_id = p.id
     WHERE pm.user_id = $1
     ORDER BY p.created_at DESC`,
    [userId]
  );
  return rows;
}

/**
 * Returns projects for /me/projects — includes branch name, display name, and
 * the timestamp of the latest commit on the user's branch.
 */
async function getProjectsWithMetaByUserId(userId) {
  const { rows } = await pool.query(
    `SELECT p.id AS project_id,
            p.name AS project_name,
            p.invite_code,
            pm.branch_name AS my_branch,
            pm.display_name,
            pm.role,
            (
              SELECT c.created_at
              FROM commits c
              JOIN branches b ON b.id = c.branch_id
              WHERE b.project_id = p.id AND b.name = pm.branch_name
              ORDER BY c.created_at DESC
              LIMIT 1
            ) AS last_activity
     FROM projects p
     JOIN project_members pm ON pm.project_id = p.id
     WHERE pm.user_id = $1
     ORDER BY p.created_at DESC`,
    [userId]
  );
  return rows;
}

// ─── Project members ─────────────────────────────────────────────────────────

async function getProjectMembers(projectId) {
  const { rows } = await pool.query(
    `SELECT pm.project_id, pm.user_id, pm.role, pm.branch_name, pm.display_name,
            u.username
     FROM project_members pm
     JOIN users u ON u.id = pm.user_id
     WHERE pm.project_id = $1`,
    [projectId]
  );
  return rows;
}

async function getProjectMember(projectId, userId) {
  const { rows } = await pool.query(
    'SELECT project_id, user_id, role, branch_name FROM project_members WHERE project_id = $1 AND user_id = $2',
    [projectId, userId]
  );
  return rows[0] || null;
}

async function addProjectMember(projectId, userId, role, branchName, displayName = '') {
  const { rows } = await pool.query(
    'INSERT INTO project_members (project_id, user_id, role, branch_name, display_name) VALUES ($1, $2, $3, $4, $5) RETURNING *',
    [projectId, userId, role, branchName, displayName]
  );
  return rows[0];
}

// ─── Branches ────────────────────────────────────────────────────────────────

async function getBranchById(id) {
  const { rows } = await pool.query(
    'SELECT id, project_id, name, created_from, created_at FROM branches WHERE id = $1',
    [id]
  );
  return rows[0] || null;
}

async function getBranchByName(projectId, name) {
  const { rows } = await pool.query(
    'SELECT id, project_id, name, created_from, created_at FROM branches WHERE project_id = $1 AND name = $2',
    [projectId, name]
  );
  return rows[0] || null;
}

async function getBranchesByProject(projectId) {
  const { rows } = await pool.query(
    'SELECT id, project_id, name, created_from, created_at FROM branches WHERE project_id = $1 ORDER BY created_at ASC',
    [projectId]
  );
  return rows;
}

async function createBranch(projectId, name, createdFrom = null) {
  const { rows } = await pool.query(
    'INSERT INTO branches (project_id, name, created_from) VALUES ($1, $2, $3) RETURNING id, project_id, name, created_from, created_at',
    [projectId, name, createdFrom]
  );
  return rows[0];
}

// ─── Commits ─────────────────────────────────────────────────────────────────

async function getLatestCommit(branchId) {
  const { rows } = await pool.query(
    'SELECT id, branch_id, project_id, author_id, message, score_data, created_at FROM commits WHERE branch_id = $1 ORDER BY created_at DESC LIMIT 1',
    [branchId]
  );
  return rows[0] || null;
}

async function getCommitsByBranch(branchId, limit = 20) {
  const { rows } = await pool.query(
    'SELECT id, branch_id, project_id, author_id, message, created_at FROM commits WHERE branch_id = $1 ORDER BY created_at DESC LIMIT $2',
    [branchId, limit]
  );
  return rows;
}

async function getCommitById(id) {
  const { rows } = await pool.query(
    'SELECT id, branch_id, project_id, author_id, message, score_data, created_at FROM commits WHERE id = $1',
    [id]
  );
  return rows[0] || null;
}

async function createCommit(branchId, projectId, authorId, message, scoreData) {
  const { rows } = await pool.query(
    'INSERT INTO commits (branch_id, project_id, author_id, message, score_data) VALUES ($1, $2, $3, $4, $5) RETURNING id, branch_id, project_id, author_id, message, created_at',
    [branchId, projectId, authorId, message, scoreData]
  );
  return rows[0];
}

// ─── Live sessions ───────────────────────────────────────────────────────────

async function createLiveSession(projectId, hostUserId) {
  const { rows } = await pool.query(
    'INSERT INTO live_sessions (project_id, host_user_id) VALUES ($1, $2) RETURNING id, project_id, host_user_id, started_at',
    [projectId, hostUserId]
  );
  return rows[0];
}

async function endLiveSession(sessionId) {
  const { rows } = await pool.query(
    'UPDATE live_sessions SET ended_at = NOW() WHERE id = $1 RETURNING *',
    [sessionId]
  );
  return rows[0] || null;
}

async function getActiveLiveSessionsByProject(projectId) {
  const { rows } = await pool.query(
    `SELECT ls.id, ls.project_id, ls.host_user_id, ls.started_at, u.username AS host_username
     FROM live_sessions ls
     JOIN users u ON u.id = ls.host_user_id
     WHERE ls.project_id = $1 AND ls.ended_at IS NULL`,
    [projectId]
  );
  return rows;
}

module.exports = {
  pool,
  initDb,
  // users
  getUserById,
  getUserByUsername,
  createUser,
  // projects
  getProjectById,
  getProjectByName,
  getProjectByInviteCode,
  createProject,
  getProjectsByUserId,
  getProjectsWithMetaByUserId,
  // members
  getProjectMembers,
  getProjectMember,
  addProjectMember,
  // branches
  getBranchById,
  getBranchByName,
  getBranchesByProject,
  createBranch,
  // commits
  getLatestCommit,
  getCommitsByBranch,
  getCommitById,
  createCommit,
  // live sessions
  createLiveSession,
  endLiveSession,
  getActiveLiveSessionsByProject,
};
