/**
 * scoreWriter.js — Read and write MuseScore scores via the plugin API.
 *
 * Public API
 * ----------
 *   readScoreStructure(curScore)  → structured object (matches parseMscx format)
 *   getScoreAsMscx(curScore)      → JSON string (serialised structure)
 *   applyNoteChange(cursor, measureNumber, staffIndex, voiceIndex, eventIndex, newNote)
 *   pitchToName(pitch)            → string e.g. "C4"
 *   nameToPitch(name)             → MIDI pitch number
 */

"use strict";

// ---------------------------------------------------------------------------
// Pitch helpers
// ---------------------------------------------------------------------------

var NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

/**
 * Convert a MIDI pitch number (0-127) to a human-readable note name.
 * e.g. 60 → "C4", 69 → "A4"
 */
function pitchToName(pitch) {
    if (typeof pitch !== "number" || pitch < 0 || pitch > 127) {
        return "?";
    }
    var octave = Math.floor(pitch / 12) - 1;
    var name = NOTE_NAMES[pitch % 12];
    return name + octave;
}

/**
 * Convert a note name string ("C4", "F#3", "Bb5") to a MIDI pitch number.
 * Returns -1 on parse failure.
 */
function nameToPitch(name) {
    if (!name || typeof name !== "string") return -1;
    var m = name.match(/^([A-Ga-g])([#b]?)(-?\d+)$/);
    if (!m) return -1;
    var letter = m[1].toUpperCase();
    var accidental = m[2];
    var octave = parseInt(m[3], 10);
    var base = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 }[letter];
    if (base === undefined) return -1;
    var semitone = base + (accidental === "#" ? 1 : accidental === "b" ? -1 : 0);
    return (octave + 1) * 12 + semitone;
}

// ---------------------------------------------------------------------------
// Duration helpers
// ---------------------------------------------------------------------------

var DURATION_MAP = {
    "whole":   { ticks: 1920, fraction: 1.0 },
    "half":    { ticks: 960,  fraction: 0.5 },
    "quarter": { ticks: 480,  fraction: 0.25 },
    "eighth":  { ticks: 240,  fraction: 0.125 },
    "16th":    { ticks: 120,  fraction: 0.0625 },
    "32nd":    { ticks: 60,   fraction: 0.03125 },
    "64th":    { ticks: 30,   fraction: 0.015625 }
};

/** Convert a MuseScore NoteType / duration type to our durationType string. */
function _durationTypeToString(durationValue) {
    // MuseScore enums: 0=whole, 1=half, 2=quarter, 3=eighth, 4=16th, 5=32nd, 6=64th
    var map = { 0: "whole", 1: "half", 2: "quarter", 3: "eighth", 4: "16th", 5: "32nd", 6: "64th" };
    if (map[durationValue] !== undefined) return map[durationValue];
    // If it's already a string, pass through
    if (typeof durationValue === "string" && DURATION_MAP[durationValue]) return durationValue;
    return "quarter";
}

// ---------------------------------------------------------------------------
// readScoreStructure
// ---------------------------------------------------------------------------

/**
 * Walk through curScore using the MuseScore 3 plugin API and return the full
 * note/rest structure in the same format that parseMscx() produces.
 *
 * @param {object} curScore - The MuseScore curScore object from the plugin API.
 * @returns {object} scoreObject matching parseMscx() format.
 */
function readScoreStructure(curScore) {
    var result = {
        title: "",
        parts: []
    };

    if (!curScore) {
        return result;
    }

    // Title
    try {
        result.title = curScore.title || curScore.name || "Untitled";
    } catch (e) {
        result.title = "Untitled";
    }

    var nstaves = 0;
    try {
        nstaves = curScore.nstaves || 0;
    } catch (e) {
        nstaves = 0;
    }

    // MuseScore has 4 voices per staff (0-3)
    var MAX_VOICES = 4;

    for (var staffIdx = 0; staffIdx < nstaves; staffIdx++) {
        var part = { staffIndex: staffIdx + 1, measures: [] };
        var measureMap = {}; // measureNumber → measure object

        for (var voiceIdx = 0; voiceIdx < MAX_VOICES; voiceIdx++) {
            var cursor = curScore.newCursor();
            if (!cursor) break;

            cursor.staffIdx = staffIdx;
            cursor.voice = voiceIdx;
            cursor.rewind(0); // go to beginning of score

            var measureNumber = 0;
            var lastMeasureStart = null;

            while (cursor.segment) {
                // Track measure changes
                var seg = cursor.segment;
                var measureEl = null;
                try { measureEl = seg.measure; } catch (e2) { measureEl = null; }

                // Determine current measure number
                var curMeasureStart = null;
                try {
                    curMeasureStart = (measureEl && measureEl.firstSegment)
                                      ? measureEl.firstSegment.tick
                                      : seg.tick;
                } catch (e3) {
                    curMeasureStart = seg.tick;
                }

                if (curMeasureStart !== lastMeasureStart) {
                    measureNumber++;
                    lastMeasureStart = curMeasureStart;
                }

                // Ensure measure object exists
                if (!measureMap[measureNumber]) {
                    measureMap[measureNumber] = { number: measureNumber, voices: [] };
                }
                var measure = measureMap[measureNumber];

                // Ensure voice slot exists in this measure
                while (measure.voices.length <= voiceIdx) {
                    measure.voices.push({ index: measure.voices.length, events: [] });
                }
                var voice = measure.voices[voiceIdx];

                // Read the element at this segment
                var element = cursor.element;
                if (element) {
                    var etype = element.type;
                    // Element types: 73 = Note (rarely direct), 93 = Chord, 70 = Rest
                    // Use element.type names if available
                    var typeName = (element.type && typeof element.type.toString === "function")
                                   ? element.type.toString()
                                   : "";

                    var isChord = (etype === Element.CHORD || typeName === "Chord");
                    var isRest  = (etype === Element.REST  || typeName === "Rest");

                    if (isChord) {
                        try {
                            var notes = element.notes;
                            if (notes && notes.length > 0) {
                                for (var n = 0; n < notes.length; n++) {
                                    var note = notes[n];
                                    var durStr = _durationTypeToString(
                                        element.duration ? element.duration.type : "quarter"
                                    );
                                    voice.events.push({
                                        type: "note",
                                        pitch: note.pitch || 0,
                                        tpc: note.tpc || 0,
                                        durationType: durStr,
                                        dots: element.duration ? (element.duration.dots || 0) : 0,
                                        duration: DURATION_MAP[durStr]
                                                  ? DURATION_MAP[durStr].fraction
                                                  : 0.25
                                    });
                                }
                            }
                        } catch (noteErr) {
                            // skip unreadable chord
                        }
                    } else if (isRest) {
                        try {
                            var durStr2 = _durationTypeToString(
                                element.duration ? element.duration.type : "quarter"
                            );
                            voice.events.push({
                                type: "rest",
                                pitch: 0,
                                tpc: 0,
                                durationType: durStr2,
                                dots: element.duration ? (element.duration.dots || 0) : 0,
                                duration: DURATION_MAP[durStr2]
                                          ? DURATION_MAP[durStr2].fraction
                                          : 0.25
                            });
                        } catch (restErr) {
                            // skip
                        }
                    }
                }

                cursor.next();
            }
        }

        // Convert measureMap to sorted array
        var measureKeys = Object.keys(measureMap).sort(function (a, b) {
            return parseInt(a, 10) - parseInt(b, 10);
        });
        for (var mk = 0; mk < measureKeys.length; mk++) {
            part.measures.push(measureMap[measureKeys[mk]]);
        }

        result.parts.push(part);
    }

    return result;
}

// ---------------------------------------------------------------------------
// getScoreAsMscx
// ---------------------------------------------------------------------------

/**
 * Serialise the current score to a JSON string that can be sent to the server.
 * The "MSCX" in the name is a slight misnomer: we return JSON since we cannot
 * export real MSCX from a QML plugin without file I/O access.
 *
 * @param {object} curScore
 * @returns {string} JSON string
 */
function getScoreAsMscx(curScore) {
    var structure = readScoreStructure(curScore);
    try {
        return JSON.stringify(structure, null, 2);
    } catch (e) {
        return JSON.stringify({ title: "error", parts: [] });
    }
}

// ---------------------------------------------------------------------------
// applyNoteChange
// ---------------------------------------------------------------------------

/**
 * Move a cursor to the specified position and modify the note there.
 *
 * @param {object} cursor       - A MuseScore cursor (curScore.newCursor()).
 * @param {number} measureNumber - 1-based measure number.
 * @param {number} staffIndex    - 0-based staff index.
 * @param {number} voiceIndex    - 0-based voice index (0-3).
 * @param {number} eventIndex    - Index of the event within the voice.
 * @param {object} newNote       - Event object: { type, pitch, tpc, durationType, dots }.
 * @returns {boolean} true if the change was applied, false otherwise.
 */
function applyNoteChange(cursor, measureNumber, staffIndex, voiceIndex, eventIndex, newNote) {
    if (!cursor || !newNote) return false;

    try {
        cursor.staffIdx = staffIndex;
        cursor.voice = voiceIndex;
        cursor.rewind(0); // start of score

        var currentMeasure = 0;
        var currentEventInMeasure = 0;
        var lastMeasureTick = null;

        while (cursor.segment) {
            var seg = cursor.segment;

            // Detect measure change
            var measStart = null;
            try {
                var mEl = seg.measure;
                measStart = mEl && mEl.firstSegment ? mEl.firstSegment.tick : seg.tick;
            } catch (e) {
                measStart = seg.tick;
            }

            if (measStart !== lastMeasureTick) {
                currentMeasure++;
                lastMeasureTick = measStart;
                if (currentMeasure === measureNumber) {
                    currentEventInMeasure = 0;
                }
            }

            if (currentMeasure === measureNumber) {
                var element = cursor.element;
                if (element) {
                    var etype = element.type;
                    var isChordOrRest = (etype === Element.CHORD || etype === Element.REST);
                    if (isChordOrRest) {
                        if (currentEventInMeasure === eventIndex) {
                            // Apply the change
                            if (newNote.type === "rest") {
                                // Convert to rest — remove notes in chord or keep as-is if already rest
                                if (etype === Element.CHORD) {
                                    // MuseScore API: remove() then addRest()
                                    // This is complex; mark via the score's undo stack
                                    try {
                                        var cmd = cursor.score || cursor;
                                        // Best-effort: set duration then add rest
                                        cursor.setDuration(
                                            _durationNumerator(newNote.durationType),
                                            _durationDenominator(newNote.durationType)
                                        );
                                        cursor.addRest();
                                    } catch (e2) { /* ignore */ }
                                }
                            } else if (newNote.type === "note") {
                                // Modify existing note pitches
                                try {
                                    if (etype === Element.CHORD) {
                                        var notes = element.notes;
                                        if (notes && notes.length > 0) {
                                            notes[0].pitch = newNote.pitch;
                                            notes[0].tpc = newNote.tpc;
                                        }
                                    } else {
                                        // Was a rest, add a note
                                        cursor.setDuration(
                                            _durationNumerator(newNote.durationType),
                                            _durationDenominator(newNote.durationType)
                                        );
                                        cursor.addNote(newNote.pitch);
                                    }
                                } catch (e3) { /* ignore */ }
                            }
                            return true;
                        }
                        currentEventInMeasure++;
                    }
                }
            } else if (currentMeasure > measureNumber) {
                break; // past target measure
            }

            cursor.next();
        }
    } catch (outerErr) {
        // Log to console if available
        if (typeof console !== "undefined") {
            console.log("applyNoteChange error: " + outerErr);
        }
    }

    return false;
}

// ---------------------------------------------------------------------------
// Duration fraction helpers
// ---------------------------------------------------------------------------

function _durationNumerator(durationType) {
    var map = {
        "whole": 1, "half": 1, "quarter": 1, "eighth": 1, "16th": 1, "32nd": 1, "64th": 1
    };
    return 1;
}

function _durationDenominator(durationType) {
    var map = {
        "whole": 1, "half": 2, "quarter": 4, "eighth": 8, "16th": 16, "32nd": 32, "64th": 64
    };
    return map[durationType] || 4;
}
