'use strict';

/**
 * mscxDiff.js
 *
 * Computes structural diffs between two parsed MuseScore JSON score objects
 * and provides a selective merge utility.
 *
 * Score shape (as sent by the MuseScore plugin):
 * {
 *   title: string,
 *   parts: [
 *     {
 *       staffIndex: number,
 *       measures: [
 *         {
 *           number: number,
 *           voices: [
 *             {
 *               index: number,
 *               events: [
 *                 { type: string, pitch: number, tpc: number, durationType: string, dots: number }
 *               ]
 *             }
 *           ]
 *         }
 *       ]
 *     }
 *   ]
 * }
 */

// ─── Internal helpers ──────────────────────────────────────────────────────────

/**
 * Deep-equality check for two event objects.
 * We compare type, pitch, tpc, durationType, and dots.
 */
function eventsEqual(a, b) {
  if (!a && !b) return true;
  if (!a || !b) return false;
  return (
    a.type === b.type &&
    a.pitch === b.pitch &&
    a.tpc === b.tpc &&
    a.durationType === b.durationType &&
    (a.dots || 0) === (b.dots || 0)
  );
}

/**
 * Build a nested lookup map for quick access to parts/measures/voices/events.
 * Map shape: staffIndex → measureNumber → voiceIndex → events[]
 */
function buildScoreMap(score) {
  const map = new Map();
  if (!score || !Array.isArray(score.parts)) return map;

  for (const part of score.parts) {
    const staffIdx = part.staffIndex;
    if (!map.has(staffIdx)) map.set(staffIdx, new Map());
    const staffMap = map.get(staffIdx);

    for (const measure of (part.measures || [])) {
      const mNum = measure.number;
      if (!staffMap.has(mNum)) staffMap.set(mNum, new Map());
      const measureMap = staffMap.get(mNum);

      for (const voice of (measure.voices || [])) {
        measureMap.set(voice.index, voice.events || []);
      }
    }
  }
  return map;
}

/**
 * Collect the set of all [staffIndex, measureNumber, voiceIndex] tuples
 * present in either score.
 */
function collectAllKeys(mapA, mapB) {
  const keys = [];

  const staffIndices = new Set([...mapA.keys(), ...mapB.keys()]);
  for (const staffIdx of staffIndices) {
    const staffA = mapA.get(staffIdx) || new Map();
    const staffB = mapB.get(staffIdx) || new Map();
    const measureNums = new Set([...staffA.keys(), ...staffB.keys()]);

    for (const mNum of measureNums) {
      const voicesA = staffA.get(mNum) || new Map();
      const voicesB = staffB.get(mNum) || new Map();
      const voiceIndices = new Set([...voicesA.keys(), ...voicesB.keys()]);

      for (const vIdx of voiceIndices) {
        keys.push({ staffIdx, mNum, vIdx });
      }
    }
  }

  // Sort for deterministic output
  keys.sort((a, b) =>
    a.staffIdx - b.staffIdx ||
    a.mNum - b.mNum ||
    a.vIdx - b.vIdx
  );

  return keys;
}

// ─── Public API ────────────────────────────────────────────────────────────────

/**
 * Compute the diff between two parsed score JSON objects.
 *
 * @param {object} scoreDataA  The "base" score (e.g. from the target branch).
 * @param {object} scoreDataB  The "theirs" score (e.g. from the source branch).
 * @returns {{ diffs: DiffEntry[], summary: { added, removed, changed, total } }}
 */
function diffScores(scoreDataA, scoreDataB) {
  const mapA = buildScoreMap(scoreDataA);
  const mapB = buildScoreMap(scoreDataB);

  const keys = collectAllKeys(mapA, mapB);
  const diffs = [];

  for (const { staffIdx, mNum, vIdx } of keys) {
    const eA = (() => {
      const sm = mapA.get(staffIdx);
      if (!sm) return [];
      const mm = sm.get(mNum);
      if (!mm) return [];
      return mm.get(vIdx) || [];
    })();

    const eB = (() => {
      const sm = mapB.get(staffIdx);
      if (!sm) return [];
      const mm = sm.get(mNum);
      if (!mm) return [];
      return mm.get(vIdx) || [];
    })();

    const maxLen = Math.max(eA.length, eB.length);

    for (let i = 0; i < maxLen; i++) {
      const eventA = eA[i] || null;
      const eventB = eB[i] || null;

      if (eventA === null && eventB !== null) {
        diffs.push({
          measureNumber: mNum,
          staffIndex: staffIdx,
          voiceIndex: vIdx,
          eventIndex: i,
          type: 'added',
          eventA: null,
          eventB,
        });
      } else if (eventA !== null && eventB === null) {
        diffs.push({
          measureNumber: mNum,
          staffIndex: staffIdx,
          voiceIndex: vIdx,
          eventIndex: i,
          type: 'removed',
          eventA,
          eventB: null,
        });
      } else if (!eventsEqual(eventA, eventB)) {
        diffs.push({
          measureNumber: mNum,
          staffIndex: staffIdx,
          voiceIndex: vIdx,
          eventIndex: i,
          type: 'changed',
          eventA,
          eventB,
        });
      }
    }
  }

  const summary = {
    added:   diffs.filter(d => d.type === 'added').length,
    removed: diffs.filter(d => d.type === 'removed').length,
    changed: diffs.filter(d => d.type === 'changed').length,
    total:   diffs.length,
  };

  return { diffs, summary };
}

/**
 * Selectively merge changes from `theirScore` into `baseScore`.
 *
 * @param {object}   baseScore            The base (target branch head) score.
 * @param {object}   theirScore           The incoming (source branch head) score.
 * @param {number[]} acceptedDiffIndices  Indices into the diffs array (from diffScores) to accept.
 * @returns {object} The merged score JSON.
 */
function mergeDiffs(baseScore, theirScore, acceptedDiffIndices = []) {
  const { diffs } = diffScores(baseScore, theirScore);
  const accepted = new Set(acceptedDiffIndices);

  // Deep-clone the base score to avoid mutations
  const merged = JSON.parse(JSON.stringify(baseScore));

  // Build a mutable lookup: staffIndex → measureNumber → voiceIndex → events[]
  // We'll point directly to the arrays inside `merged` so we can mutate them.
  function getMergedEvents(staffIndex, measureNumber, voiceIndex) {
    let part = merged.parts.find(p => p.staffIndex === staffIndex);
    if (!part) {
      part = { staffIndex, measures: [] };
      merged.parts.push(part);
    }
    let measure = part.measures.find(m => m.number === measureNumber);
    if (!measure) {
      measure = { number: measureNumber, voices: [] };
      part.measures.push(measure);
    }
    let voice = measure.voices.find(v => v.index === voiceIndex);
    if (!voice) {
      voice = { index: voiceIndex, events: [] };
      measure.voices.push(voice);
    }
    return voice.events;
  }

  // Apply accepted diffs in reverse index order within each voice so that
  // insertions/deletions don't shift subsequent indices.
  // Group by (staffIndex, measureNumber, voiceIndex) first.
  const grouped = new Map();
  for (let i = 0; i < diffs.length; i++) {
    if (!accepted.has(i)) continue;
    const d = diffs[i];
    const key = `${d.staffIndex}:${d.measureNumber}:${d.voiceIndex}`;
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key).push({ diffIndex: i, diff: d });
  }

  for (const entries of grouped.values()) {
    // Sort descending by eventIndex so splices don't invalidate earlier indices
    entries.sort((a, b) => b.diff.eventIndex - a.diff.eventIndex);

    for (const { diff } of entries) {
      const events = getMergedEvents(diff.staffIndex, diff.measureNumber, diff.voiceIndex);
      const idx = diff.eventIndex;

      if (diff.type === 'added') {
        // Insert eventB at position idx
        events.splice(idx, 0, diff.eventB);
      } else if (diff.type === 'removed') {
        // Remove the event at idx (it exists in base but not in theirs)
        events.splice(idx, 1);
      } else if (diff.type === 'changed') {
        // Replace with theirs
        events[idx] = diff.eventB;
      }
    }
  }

  return merged;
}

// ─── Measure-level diff helpers ───────────────────────────────────────────────

/**
 * Convert a MIDI pitch number to a human-readable note name.
 * E.g. 60 → "C4", 61 → "C#4", 69 → "A4"
 *
 * @param {number} pitch  MIDI pitch value (0–127)
 * @returns {string}
 */
function pitchToName(pitch) {
  if (pitch == null || typeof pitch !== 'number') return '?';
  const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const octave = Math.floor(pitch / 12) - 1;
  const name = noteNames[pitch % 12];
  return `${name}${octave}`;
}

/**
 * Build a human-readable summary of pitches in a measure's voice 0.
 *
 * @param {object} part        A part object with `measures` array
 * @param {number} measureNum  The measure number
 * @returns {string}  Space-separated note names, e.g. "C4 D4 E4 G4"
 */
function buildMeasureSummary(part, measureNum) {
  if (!part || !Array.isArray(part.measures)) return '';
  const measure = part.measures.find(m => m.number === measureNum);
  if (!measure) return '';
  const voice0 = (measure.voices || []).find(v => v.index === 0);
  if (!voice0) return '';
  return (voice0.events || [])
    .filter(e => e && e.type === 'note' && e.pitch != null)
    .map(e => pitchToName(e.pitch))
    .join(' ');
}

/**
 * Compute a measure-level diff between two score objects.
 *
 * For each measure number that differs (across any staff), returns an entry
 * describing what changed. Entries are sorted by measureNumber.
 *
 * @param {object} scoreDataA  Base score
 * @param {object} scoreDataB  Their score
 * @returns {Array<{
 *   measureNumber: number,
 *   staffIndex: number,
 *   status: 'modified'|'added'|'removed',
 *   summaryA: string,
 *   summaryB: string,
 *   eventDiffs: Array
 * }>}
 */
function getMeasureDiff(scoreDataA, scoreDataB) {
  const { diffs } = diffScores(scoreDataA, scoreDataB);

  // Collect all distinct (measureNumber, staffIndex) pairs that have any diff
  const changedKeys = new Map(); // key: `${mNum}:${staffIdx}` → { mNum, staffIdx }
  for (const d of diffs) {
    const k = `${d.measureNumber}:${d.staffIndex}`;
    if (!changedKeys.has(k)) {
      changedKeys.set(k, { mNum: d.measureNumber, staffIdx: d.staffIndex });
    }
  }

  // Also find measures present in only one score (added/removed staves or measures)
  const mapA = buildScoreMap(scoreDataA);
  const mapB = buildScoreMap(scoreDataB);
  const allStaff = new Set([...mapA.keys(), ...mapB.keys()]);

  for (const staffIdx of allStaff) {
    const staffA = mapA.get(staffIdx) || new Map();
    const staffB = mapB.get(staffIdx) || new Map();
    const allMeasures = new Set([...staffA.keys(), ...staffB.keys()]);
    for (const mNum of allMeasures) {
      const k = `${mNum}:${staffIdx}`;
      if (!changedKeys.has(k)) {
        const inA = staffA.has(mNum);
        const inB = staffB.has(mNum);
        if (inA !== inB) {
          changedKeys.set(k, { mNum, staffIdx });
        }
      }
    }
  }

  const result = [];

  for (const { mNum, staffIdx } of changedKeys.values()) {
    const staffA = mapA.get(staffIdx) || new Map();
    const staffB = mapB.get(staffIdx) || new Map();
    const inA = staffA.has(mNum);
    const inB = staffB.has(mNum);

    let status;
    if (inA && inB) {
      status = 'modified';
    } else if (!inA && inB) {
      status = 'added';
    } else {
      status = 'removed';
    }

    // Get summaries per staff part
    const partA = (scoreDataA && Array.isArray(scoreDataA.parts))
      ? scoreDataA.parts.find(p => p.staffIndex === staffIdx)
      : null;
    const partB = (scoreDataB && Array.isArray(scoreDataB.parts))
      ? scoreDataB.parts.find(p => p.staffIndex === staffIdx)
      : null;

    const summaryA = buildMeasureSummary(partA, mNum);
    const summaryB = buildMeasureSummary(partB, mNum);

    // Collect event diffs that belong to this (measureNumber, staffIndex)
    const eventDiffs = diffs.filter(
      d => d.measureNumber === mNum && d.staffIndex === staffIdx
    );

    result.push({
      measureNumber: mNum,
      staffIndex: staffIdx,
      status,
      summaryA,
      summaryB,
      eventDiffs,
    });
  }

  // Sort by measure number, then staff index
  result.sort((a, b) => a.measureNumber - b.measureNumber || a.staffIndex - b.staffIndex);
  return result;
}

/**
 * Extract a subset of measures from a score.
 *
 * Returns a new score object with the same structure (title, parts/staves)
 * but only containing measures whose `number` is in `measureNumbers`.
 *
 * @param {object}   score           Parsed score JSON
 * @param {number[]} measureNumbers  Array of measure numbers to keep
 * @returns {object}  New score with only the requested measures
 */
function extractMeasures(score, measureNumbers) {
  if (!score || !Array.isArray(score.parts)) return score;
  const wantSet = new Set(measureNumbers);

  const newScore = JSON.parse(JSON.stringify(score));
  for (const part of newScore.parts) {
    part.measures = (part.measures || []).filter(m => wantSet.has(m.number));
  }
  return newScore;
}

/**
 * Import specific measures from `sourceScore` into `targetScore`.
 *
 * For each measure number in `measureNumbers`:
 *   - If it exists in source, replace (or append) the measure in the target.
 * Stave structure is preserved. Deep-clones target first.
 *
 * @param {object}   targetScore     The score to merge into (e.g. main branch)
 * @param {object}   sourceScore     The score to pull measures from
 * @param {number[]} measureNumbers  Measure numbers to import
 * @returns {object}  Merged score
 */
function importMeasures(targetScore, sourceScore, measureNumbers) {
  if (!targetScore || !sourceScore) return targetScore;
  const merged = JSON.parse(JSON.stringify(targetScore));
  const wantSet = new Set(measureNumbers);

  const sourceParts = Array.isArray(sourceScore.parts) ? sourceScore.parts : [];

  for (const srcPart of sourceParts) {
    const staffIdx = srcPart.staffIndex;

    // Find or create matching part in merged score
    let tgtPart = merged.parts.find(p => p.staffIndex === staffIdx);
    if (!tgtPart) {
      tgtPart = { staffIndex: staffIdx, measures: [] };
      merged.parts.push(tgtPart);
    }

    for (const srcMeasure of (srcPart.measures || [])) {
      if (!wantSet.has(srcMeasure.number)) continue;

      const existingIdx = tgtPart.measures.findIndex(m => m.number === srcMeasure.number);
      const clonedMeasure = JSON.parse(JSON.stringify(srcMeasure));

      if (existingIdx !== -1) {
        // Replace existing measure
        tgtPart.measures[existingIdx] = clonedMeasure;
      } else {
        // Append; then sort by measure number
        tgtPart.measures.push(clonedMeasure);
      }
    }

    // Keep measures sorted by number
    tgtPart.measures.sort((a, b) => a.number - b.number);
  }

  return merged;
}

module.exports = {
  diffScores,
  mergeDiffs,
  getMeasureDiff,
  extractMeasures,
  importMeasures,
  pitchToName,
};
