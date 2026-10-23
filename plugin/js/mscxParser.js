/**
 * mscxParser.js — MSCX XML parser, differ, and patch applier.
 *
 * Qt's JS engine supports DOMParser when running inside a QML environment
 * that has loaded QtWebEngine or QtXmlPatterns. Where it is absent we fall
 * back to a regex-based mini-parser.  All three public entry-points work with
 * either code path.
 *
 * Public API
 * ----------
 *   parseMscx(xmlString)          → scoreObject
 *   diffScores(scoreA, scoreB)    → diffArray
 *   applyAcceptedChanges(originalMscxString, diffs, acceptedIndices)  → xmlString
 */

"use strict";

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/** Escape special regex characters in a literal string. */
function escapeRe(s) {
    return s.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&");
}

/**
 * Very small regex-based XML query helpers used when DOMParser is unavailable.
 * These are intentionally narrow—they only need to handle well-formed MSCX.
 */
var RE = {
    /** Extract the inner text of the FIRST occurrence of <tag>…</tag>. */
    innerText: function (xml, tag) {
        var re = new RegExp("<" + tag + "[^>]*>([\\s\\S]*?)<\\/" + tag + ">", "i");
        var m = xml.match(re);
        return m ? m[1].trim() : "";
    },

    /** Extract content of ALL occurrences of <tag>…</tag> as an array. */
    allBlocks: function (xml, tag) {
        var re = new RegExp("<" + tag + "(?:\\s[^>]*)?>([\\s\\S]*?)<\\/" + tag + ">", "gi");
        var results = [];
        var m;
        while ((m = re.exec(xml)) !== null) {
            results.push(m[1]);
        }
        return results;
    },

    /** Read a specific attribute value from the FIRST match of a tag. */
    attr: function (xml, tag, attrName) {
        var re = new RegExp("<" + tag + "[^>]*\\s" + attrName + "=[\"']([^\"']*)[\"']", "i");
        var m = xml.match(re);
        return m ? m[1] : "";
    }
};

// ---------------------------------------------------------------------------
// DOM helper — works whether or not DOMParser exists
// ---------------------------------------------------------------------------

function parseXml(xmlString) {
    if (typeof DOMParser !== "undefined") {
        try {
            var parser = new DOMParser();
            var doc = parser.parseFromString(xmlString, "text/xml");
            // Check for parse errors (Firefox/Chrome style)
            if (doc.querySelector && doc.querySelector("parsererror")) {
                return null;
            }
            return doc;
        } catch (e) {
            return null;
        }
    }
    return null; // signal: use regex path
}

function domText(parent, tagName) {
    if (!parent) return "";
    var el = parent.getElementsByTagName ? parent.getElementsByTagName(tagName)[0] : null;
    return el ? (el.textContent || el.innerText || "").trim() : "";
}

function domAttr(el, attrName) {
    if (!el || !el.getAttribute) return "";
    return el.getAttribute(attrName) || "";
}

// ---------------------------------------------------------------------------
// parseMscx
// ---------------------------------------------------------------------------

/**
 * Parse an MSCX XML string into a structured JS object.
 *
 * Returns:
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
 *                 { type, pitch, tpc, durationType, dots, duration }
 *               ]
 *             }
 *           ]
 *         }
 *       ]
 *     }
 *   ]
 * }
 */
function parseMscx(xmlString) {
    if (!xmlString || typeof xmlString !== "string") {
        return { title: "", parts: [] };
    }

    var doc = parseXml(xmlString);

    if (doc) {
        return _parseMscxDom(doc, xmlString);
    } else {
        return _parseMscxRegex(xmlString);
    }
}

// --- DOM path ---

function _parseMscxDom(doc, xmlString) {
    var result = { title: "", parts: [] };

    // Title: look in Score > metaTag[name="title"] or first Text > html-data
    var metaTags = doc.getElementsByTagName("metaTag");
    for (var m = 0; m < metaTags.length; m++) {
        if (domAttr(metaTags[m], "name") === "title") {
            result.title = (metaTags[m].textContent || "").trim();
            break;
        }
    }
    if (!result.title) {
        result.title = domText(doc, "Title") || "Untitled";
    }

    var staves = doc.getElementsByTagName("Staff");
    for (var s = 0; s < staves.length; s++) {
        var staffEl = staves[s];
        var staffId = parseInt(domAttr(staffEl, "id"), 10) || (s + 1);
        var part = { staffIndex: staffId, measures: [] };

        var measures = staffEl.getElementsByTagName("Measure");
        for (var mIdx = 0; mIdx < measures.length; mIdx++) {
            var mEl = measures[mIdx];
            var measureNum = parseInt(domAttr(mEl, "number"), 10) || (mIdx + 1);
            var measure = { number: measureNum, voices: [] };

            // Collect voices: implicit voice 0 = notes not in <voice> tag,
            // explicit <voice> tags numbered by order.
            var voiceMap = {};

            function collectEvents(containerEl, voiceIdx) {
                if (!voiceMap[voiceIdx]) {
                    voiceMap[voiceIdx] = { index: voiceIdx, events: [] };
                }
                var children = containerEl.childNodes;
                for (var c = 0; c < children.length; c++) {
                    var child = children[c];
                    var nodeName = child.nodeName || child.tagName || "";
                    if (nodeName === "Chord") {
                        var noteEls = child.getElementsByTagName("Note");
                        for (var n = 0; n < noteEls.length; n++) {
                            var noteEl = noteEls[n];
                            var durType = domText(child, "durationType");
                            var dotsEl = child.getElementsByTagName("dots")[0];
                            voiceMap[voiceIdx].events.push({
                                type: "note",
                                pitch: parseInt(domText(noteEl, "pitch"), 10) || 0,
                                tpc: parseInt(domText(noteEl, "tpc"), 10) || 0,
                                durationType: durType || "quarter",
                                dots: dotsEl ? parseInt(dotsEl.textContent, 10) || 0 : 0,
                                duration: _durationToFraction(durType)
                            });
                        }
                        if (noteEls.length === 0) {
                            // Chord with no notes = chord rest? unlikely, skip
                        }
                    } else if (nodeName === "Rest") {
                        var durType2 = domText(child, "durationType");
                        voiceMap[voiceIdx].events.push({
                            type: "rest",
                            pitch: 0,
                            tpc: 0,
                            durationType: durType2 || "quarter",
                            dots: 0,
                            duration: _durationToFraction(durType2)
                        });
                    } else if (nodeName === "voice") {
                        // nested <voice> blocks in older MSCX: not standard, ignore
                    }
                }
            }

            // Scan for explicit <voice> children of the measure
            var mChildren = mEl.childNodes;
            var foundVoiceTags = false;
            for (var vc = 0; vc < mChildren.length; vc++) {
                var vChild = mChildren[vc];
                var vName = vChild.nodeName || vChild.tagName || "";
                if (vName === "voice") {
                    foundVoiceTags = true;
                    // MuseScore 4 uses <voice> wrapper elements, numbered by position
                    var voiceIdx = Array.prototype.indexOf.call(mChildren, vChild);
                    // Count only voice tags to get the 0-based voice index
                    var vTagIdx = 0;
                    for (var vi2 = 0; vi2 < vc; vi2++) {
                        if ((mChildren[vi2].nodeName || mChildren[vi2].tagName) === "voice") {
                            vTagIdx++;
                        }
                    }
                    collectEvents(vChild, vTagIdx);
                }
            }
            if (!foundVoiceTags) {
                // MuseScore 3 flat structure: Chord/Rest directly in Measure
                collectEvents(mEl, 0);
            }

            // Convert voiceMap to array
            var voiceKeys = Object.keys(voiceMap).sort(function (a, b) {
                return parseInt(a, 10) - parseInt(b, 10);
            });
            for (var vk = 0; vk < voiceKeys.length; vk++) {
                measure.voices.push(voiceMap[voiceKeys[vk]]);
            }
            if (measure.voices.length === 0) {
                measure.voices.push({ index: 0, events: [] });
            }
            part.measures.push(measure);
        }

        result.parts.push(part);
    }

    return result;
}

// --- Regex fallback path ---

function _parseMscxRegex(xmlString) {
    var result = { title: "", parts: [] };

    // Title
    var titleMatch = xmlString.match(/<metaTag\s+name=["']title["'][^>]*>([\s\S]*?)<\/metaTag>/i);
    result.title = titleMatch ? titleMatch[1].trim() : "Untitled";

    // Staves
    var staffRe = /<Staff\s+id=["']?(\d+)["']?>([\s\S]*?)<\/Staff>/gi;
    var staffMatch;
    while ((staffMatch = staffRe.exec(xmlString)) !== null) {
        var staffId = parseInt(staffMatch[1], 10);
        var staffContent = staffMatch[2];
        var part = { staffIndex: staffId, measures: [] };

        var measureRe = /<Measure(?:\s+number=["']?(\d+)["']?)?>([\s\S]*?)<\/Measure>/gi;
        var measureMatch;
        var autoMeasureNum = 0;
        while ((measureMatch = measureRe.exec(staffContent)) !== null) {
            autoMeasureNum++;
            var measureNum = measureMatch[1]
                             ? parseInt(measureMatch[1], 10)
                             : autoMeasureNum;
            var measureContent = measureMatch[2];
            var measure = { number: measureNum, voices: [] };

            // Try <voice> wrapper tags first
            var voiceRe = /<voice>([\s\S]*?)<\/voice>/gi;
            var voiceMatch;
            var voiceIdx = 0;
            var foundVoiceTags = false;
            while ((voiceMatch = voiceRe.exec(measureContent)) !== null) {
                foundVoiceTags = true;
                var events = _extractEventsRegex(voiceMatch[1]);
                measure.voices.push({ index: voiceIdx, events: events });
                voiceIdx++;
            }
            if (!foundVoiceTags) {
                var events0 = _extractEventsRegex(measureContent);
                measure.voices.push({ index: 0, events: events0 });
            }
            part.measures.push(measure);
        }

        result.parts.push(part);
    }

    return result;
}

function _extractEventsRegex(content) {
    var events = [];

    // Match Chord and Rest blocks
    var elemRe = /<(Chord|Rest)>([\s\S]*?)<\/(Chord|Rest)>/gi;
    var elemMatch;
    while ((elemMatch = elemRe.exec(content)) !== null) {
        var elemType = elemMatch[1].toLowerCase();
        var elemContent = elemMatch[2];

        if (elemType === "chord") {
            // Each <Note> inside the chord
            var noteRe = /<Note>([\s\S]*?)<\/Note>/gi;
            var noteMatch;
            while ((noteMatch = noteRe.exec(elemContent)) !== null) {
                var noteContent = noteMatch[1];
                var pitch = _tagInt(noteContent, "pitch");
                var tpc = _tagInt(noteContent, "tpc");
                var durationType = _tagStr(elemContent, "durationType") || "quarter";
                var dots = _tagInt(elemContent, "dots");
                events.push({
                    type: "note",
                    pitch: pitch,
                    tpc: tpc,
                    durationType: durationType,
                    dots: dots,
                    duration: _durationToFraction(durationType)
                });
            }
        } else {
            var durationType2 = _tagStr(elemContent, "durationType") || "quarter";
            events.push({
                type: "rest",
                pitch: 0,
                tpc: 0,
                durationType: durationType2,
                dots: 0,
                duration: _durationToFraction(durationType2)
            });
        }
    }
    return events;
}

function _tagInt(xml, tag) {
    var re = new RegExp("<" + tag + ">(\\d+)<\\/" + tag + ">", "i");
    var m = xml.match(re);
    return m ? parseInt(m[1], 10) : 0;
}

function _tagStr(xml, tag) {
    var re = new RegExp("<" + tag + ">([^<]*)<\\/" + tag + ">", "i");
    var m = xml.match(re);
    return m ? m[1].trim() : "";
}

function _durationToFraction(dt) {
    var map = {
        "whole": 1.0,
        "half": 0.5,
        "quarter": 0.25,
        "eighth": 0.125,
        "16th": 0.0625,
        "32nd": 0.03125,
        "64th": 0.015625
    };
    return map[dt] !== undefined ? map[dt] : 0.25;
}

// ---------------------------------------------------------------------------
// diffScores
// ---------------------------------------------------------------------------

/**
 * Compute a diff between two parsed score objects.
 *
 * Returns an array of:
 * {
 *   measureNumber: number,
 *   staffIndex: number,
 *   voiceIndex: number,
 *   type: 'added' | 'removed' | 'changed',
 *   eventIndex: number,
 *   eventA: object | null,
 *   eventB: object | null
 * }
 */
function diffScores(scoreA, scoreB) {
    var diffs = [];

    // Build lookup maps indexed by [staffIndex][measureNumber]
    var mapA = _buildLookup(scoreA);
    var mapB = _buildLookup(scoreB);

    // Collect all staff indices that appear in either score
    var allStaff = _mergeKeys(mapA, mapB);

    for (var si = 0; si < allStaff.length; si++) {
        var staffIdx = allStaff[si];
        var staffA = mapA[staffIdx] || {};
        var staffB = mapB[staffIdx] || {};
        var allMeasures = _mergeKeys(staffA, staffB);

        for (var mi = 0; mi < allMeasures.length; mi++) {
            var mNum = parseInt(allMeasures[mi], 10);
            var measA = staffA[mNum];
            var measB = staffB[mNum];

            // Ensure we have voice arrays
            var voicesA = (measA && measA.voices) ? measA.voices : [];
            var voicesB = (measB && measB.voices) ? measB.voices : [];

            // Max voice count
            var numVoices = Math.max(voicesA.length, voicesB.length, 1);

            for (var vi = 0; vi < numVoices; vi++) {
                var voiceA = voicesA[vi] || { index: vi, events: [] };
                var voiceB = voicesB[vi] || { index: vi, events: [] };
                var eventsA = voiceA.events || [];
                var eventsB = voiceB.events || [];
                var len = Math.max(eventsA.length, eventsB.length);

                for (var ei = 0; ei < len; ei++) {
                    var evA = ei < eventsA.length ? eventsA[ei] : null;
                    var evB = ei < eventsB.length ? eventsB[ei] : null;

                    if (evA === null && evB !== null) {
                        diffs.push({
                            measureNumber: mNum,
                            staffIndex: staffIdx,
                            voiceIndex: vi,
                            type: "added",
                            eventIndex: ei,
                            eventA: null,
                            eventB: evB
                        });
                    } else if (evA !== null && evB === null) {
                        diffs.push({
                            measureNumber: mNum,
                            staffIndex: staffIdx,
                            voiceIndex: vi,
                            type: "removed",
                            eventIndex: ei,
                            eventA: evA,
                            eventB: null
                        });
                    } else if (evA !== null && evB !== null) {
                        if (!_eventsEqual(evA, evB)) {
                            diffs.push({
                                measureNumber: mNum,
                                staffIndex: staffIdx,
                                voiceIndex: vi,
                                type: "changed",
                                eventIndex: ei,
                                eventA: evA,
                                eventB: evB
                            });
                        }
                    }
                }
            }
        }
    }

    // Sort by measure number, then staff, then voice, then event
    diffs.sort(function (a, b) {
        if (a.measureNumber !== b.measureNumber) return a.measureNumber - b.measureNumber;
        if (a.staffIndex !== b.staffIndex) return a.staffIndex - b.staffIndex;
        if (a.voiceIndex !== b.voiceIndex) return a.voiceIndex - b.voiceIndex;
        return a.eventIndex - b.eventIndex;
    });

    return diffs;
}

function _buildLookup(score) {
    // Returns { [staffIndex]: { [measureNumber]: measureObject } }
    var lookup = {};
    if (!score || !score.parts) return lookup;
    for (var p = 0; p < score.parts.length; p++) {
        var part = score.parts[p];
        var si = part.staffIndex;
        lookup[si] = {};
        for (var m = 0; m < part.measures.length; m++) {
            var meas = part.measures[m];
            lookup[si][meas.number] = meas;
        }
    }
    return lookup;
}

function _mergeKeys(objA, objB) {
    var keySet = {};
    var k;
    for (k in objA) {
        if (Object.prototype.hasOwnProperty.call(objA, k)) keySet[k] = true;
    }
    for (k in objB) {
        if (Object.prototype.hasOwnProperty.call(objB, k)) keySet[k] = true;
    }
    return Object.keys(keySet).sort(function (a, b) {
        return parseInt(a, 10) - parseInt(b, 10);
    });
}

function _eventsEqual(evA, evB) {
    return evA.type === evB.type
        && evA.pitch === evB.pitch
        && evA.tpc === evB.tpc
        && evA.durationType === evB.durationType
        && evA.dots === evB.dots;
}

// ---------------------------------------------------------------------------
// applyAcceptedChanges
// ---------------------------------------------------------------------------

/**
 * Merge accepted diff entries back into the original MSCX XML string.
 *
 * @param {string}   originalMscxString  - The base MSCX file content.
 * @param {Array}    diffs               - Array from diffScores().
 * @param {Array}    acceptedIndices     - Indices into `diffs` to apply.
 * @returns {string} New MSCX XML with accepted changes.
 *
 * Strategy: re-parse the original, apply note-level patches in the structured
 * representation, then re-serialise to XML.  This avoids brittle in-place
 * string surgery and keeps the output well-formed.
 */
function applyAcceptedChanges(originalMscxString, diffs, acceptedIndices) {
    if (!originalMscxString || !diffs || !acceptedIndices || acceptedIndices.length === 0) {
        return originalMscxString;
    }

    var parsed = parseMscx(originalMscxString);
    var lookup = _buildLookup(parsed);

    for (var i = 0; i < acceptedIndices.length; i++) {
        var idx = acceptedIndices[i];
        if (idx < 0 || idx >= diffs.length) continue;
        var diff = diffs[idx];

        var staffData = lookup[diff.staffIndex];
        if (!staffData) continue;
        var measureData = staffData[diff.measureNumber];
        if (!measureData) continue;
        var voice = measureData.voices[diff.voiceIndex];
        if (!voice) continue;
        var events = voice.events;

        if (diff.type === "added" && diff.eventB) {
            if (diff.eventIndex >= events.length) {
                events.push(_cloneEvent(diff.eventB));
            } else {
                events.splice(diff.eventIndex, 0, _cloneEvent(diff.eventB));
            }
        } else if (diff.type === "removed") {
            if (diff.eventIndex < events.length) {
                events.splice(diff.eventIndex, 1);
            }
        } else if (diff.type === "changed" && diff.eventB) {
            if (diff.eventIndex < events.length) {
                events[diff.eventIndex] = _cloneEvent(diff.eventB);
            }
        }
    }

    // Re-serialise the patched score back to MSCX XML
    return _serialiseToMscx(parsed, originalMscxString);
}

function _cloneEvent(ev) {
    return {
        type: ev.type,
        pitch: ev.pitch,
        tpc: ev.tpc,
        durationType: ev.durationType,
        dots: ev.dots,
        duration: ev.duration
    };
}

/**
 * Serialise a parsed score object back to MSCX XML.
 * Preserves the original XML header, metadata, layout attributes etc. by
 * doing targeted replacements of Staff content blocks only.
 */
function _serialiseToMscx(parsedScore, originalXml) {
    var output = originalXml;

    for (var p = 0; p < parsedScore.parts.length; p++) {
        var part = parsedScore.parts[p];
        var staffId = part.staffIndex;

        // Build replacement Staff content
        var newStaffContent = _serialiseStaff(part);

        // Replace in original XML: find <Staff id="N">...</Staff>
        var re = new RegExp(
            "(<Staff\\s+id=[\"']?" + staffId + "[\"']?\\s*>)([\\s\\S]*?)(<\\/Staff>)",
            "i"
        );
        output = output.replace(re, "$1" + newStaffContent + "$3");
    }

    return output;
}

function _serialiseStaff(part) {
    var lines = [];
    for (var m = 0; m < part.measures.length; m++) {
        var measure = part.measures[m];
        lines.push('      <Measure number="' + measure.number + '">');
        for (var v = 0; v < measure.voices.length; v++) {
            var voice = measure.voices[v];
            lines.push("        <voice>");
            for (var e = 0; e < voice.events.length; e++) {
                var ev = voice.events[e];
                if (ev.type === "rest") {
                    lines.push("          <Rest>");
                    lines.push("            <durationType>" + ev.durationType + "</durationType>");
                    if (ev.dots) {
                        lines.push("            <dots>" + ev.dots + "</dots>");
                    }
                    lines.push("          </Rest>");
                } else {
                    lines.push("          <Chord>");
                    lines.push("            <durationType>" + ev.durationType + "</durationType>");
                    if (ev.dots) {
                        lines.push("            <dots>" + ev.dots + "</dots>");
                    }
                    lines.push("            <Note>");
                    lines.push("              <pitch>" + ev.pitch + "</pitch>");
                    lines.push("              <tpc>" + ev.tpc + "</tpc>");
                    lines.push("            </Note>");
                    lines.push("          </Chord>");
                }
            }
            lines.push("        </voice>");
        }
        lines.push("      </Measure>");
    }
    return "\n" + lines.join("\n") + "\n    ";
}
