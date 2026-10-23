// DiffViewer.qml
// Displays a structured diff between two score versions.
// Each row shows measure, staff, voice, event description, and Accept/Reject toggles.

import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

Rectangle {
    id: root

    // -----------------------------------------------------------------------
    // Public properties
    // -----------------------------------------------------------------------
    // Array of diff objects from mscxParser.diffScores():
    // { measureNumber, staffIndex, voiceIndex, type, eventIndex, eventA, eventB }
    property var    diffData:       []
    property string baseScoreTitle: "Base"
    property string theirScoreTitle: "Theirs"

    // -----------------------------------------------------------------------
    // Signals
    // -----------------------------------------------------------------------
    signal changesApplied(var acceptedIndices)
    signal closed()

    // -----------------------------------------------------------------------
    // Internal state
    // -----------------------------------------------------------------------
    // acceptedSet[i] = true means diff[i] is accepted
    property var _acceptedSet: ({})
    property int _acceptedCount: 0

    // -----------------------------------------------------------------------
    // Appearance
    // -----------------------------------------------------------------------
    color:  "#1e1e2e"
    radius: 8

    // -----------------------------------------------------------------------
    // Re-build the list model whenever diffData changes
    // -----------------------------------------------------------------------
    onDiffDataChanged: {
        root._acceptedSet  = ({})
        root._acceptedCount = 0
        _rebuildModel()
    }

    ListModel { id: diffModel }

    function _rebuildModel() {
        diffModel.clear()
        var diffs = root.diffData || []
        for (var i = 0; i < diffs.length; i++) {
            var d = diffs[i]
            diffModel.append({
                diffIndex:     i,
                measureNumber: d.measureNumber  || 0,
                staffIndex:    d.staffIndex     || 1,
                voiceIndex:    d.voiceIndex     || 0,
                diffType:      d.type           || "changed",
                description:   _describe(d),
                accepted:      false
            })
        }
        _recalcAccepted()
    }

    function _describe(d) {
        function _noteName(ev) {
            if (!ev) return "—"
            if (ev.type === "rest") return "rest (" + (ev.durationType || "?") + ")"
            var names = ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"]
            var octave = Math.floor((ev.pitch || 0) / 12) - 1
            var name   = names[(ev.pitch || 0) % 12] + octave
            return name + " " + (ev.durationType || "quarter")
        }

        var prefix = "Voice " + ((d.voiceIndex || 0) + 1) + " | Event #" + ((d.eventIndex || 0) + 1) + ": "
        if (d.type === "added")   return prefix + "＋ " + _noteName(d.eventB)
        if (d.type === "removed") return prefix + "－ " + _noteName(d.eventA)
        if (d.type === "changed") return prefix + _noteName(d.eventA) + " → " + _noteName(d.eventB)
        return prefix + "?"
    }

    function _recalcAccepted() {
        var count = 0
        var keys  = Object.keys(root._acceptedSet)
        for (var k = 0; k < keys.length; k++) {
            if (root._acceptedSet[keys[k]]) count++
        }
        root._acceptedCount = count
    }

    function _setAccepted(diffIndex, value) {
        var copy = root._acceptedSet
        copy[diffIndex] = value
        root._acceptedSet = copy
        // Update model row
        for (var i = 0; i < diffModel.count; i++) {
            if (diffModel.get(i).diffIndex === diffIndex) {
                diffModel.setProperty(i, "accepted", value)
                break
            }
        }
        _recalcAccepted()
    }

    function _acceptAll() {
        var copy = ({})
        for (var i = 0; i < diffModel.count; i++) {
            var idx = diffModel.get(i).diffIndex
            copy[idx] = true
            diffModel.setProperty(i, "accepted", true)
        }
        root._acceptedSet   = copy
        root._acceptedCount = diffModel.count
    }

    function _rejectAll() {
        root._acceptedSet   = ({})
        root._acceptedCount = 0
        for (var i = 0; i < diffModel.count; i++) {
            diffModel.setProperty(i, "accepted", false)
        }
    }

    function _applyAccepted() {
        var indices = []
        var keys = Object.keys(root._acceptedSet)
        for (var k = 0; k < keys.length; k++) {
            if (root._acceptedSet[keys[k]]) {
                indices.push(parseInt(keys[k], 10))
            }
        }
        indices.sort(function (a, b) { return a - b })
        root.changesApplied(indices)
    }

    // -----------------------------------------------------------------------
    // Diff-type colour helpers
    // -----------------------------------------------------------------------
    function _rowBg(dtype) {
        if (dtype === "added")   return "#1a2a1a" // green tint
        if (dtype === "removed") return "#2a1a1a" // red tint
        return "#2a2a1a"                           // yellow tint (changed)
    }
    function _typeColor(dtype) {
        if (dtype === "added")   return "#a6e3a1"
        if (dtype === "removed") return "#f38ba8"
        return "#f9e2af"
    }
    function _typeBadge(dtype) {
        if (dtype === "added")   return "＋ ADDED"
        if (dtype === "removed") return "－ REMOVED"
        return "~ CHANGED"
    }

    // -----------------------------------------------------------------------
    // Main layout
    // -----------------------------------------------------------------------
    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        // ---- Header ----
        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2
                Text {
                    text:  "🔀  Diff Viewer"
                    font { pixelSize: 20; bold: true }
                    color: "#cdd6f4"
                }
                Text {
                    text:  "Comparing: " + root.baseScoreTitle + " ↔ " + root.theirScoreTitle
                    color: "#a6adc8"
                    font.pixelSize: 12
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text:   "✕ Close"
                contentItem: Text { text: parent.text; color: "#f38ba8"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { color: parent.pressed ? "#313244" : "transparent"; radius: 4; border.color: "#f38ba8"; border.width: 1 }
                onClicked: root.closed()
            }
        }

        Rectangle { height: 1; color: "#313244"; Layout.fillWidth: true }

        // ---- Empty state ----
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: diffModel.count === 0

            Text {
                anchors.centerIn: parent
                text:    "No differences found."
                color:   "#585b70"
                font.pixelSize: 16
            }
        }

        // ---- Diff list (grouped by measure) ----
        ListView {
            id:     diffList
            model:  diffModel
            visible: diffModel.count > 0
            Layout.fillWidth:  true
            Layout.fillHeight: true
            clip: true
            spacing: 4

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            // Section header delegate (measure number)
            section.property: "measureNumber"
            section.delegate: Rectangle {
                width:  diffList.width
                height: 28
                color:  "#181825"
                radius: 4

                Text {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text:  "Measure " + section
                    color: "#89b4fa"
                    font { pixelSize: 13; bold: true }
                }
            }

            // Row delegate
            delegate: Rectangle {
                id:     diffRow
                width:  diffList.width
                height: 52
                radius: 4
                color:  _rowBg(model.diffType)

                // Accepted highlight overlay
                Rectangle {
                    anchors.fill: parent
                    radius:       parent.radius
                    color:        model.accepted ? "#203040" : "transparent"
                    border.color: model.accepted ? "#89b4fa" : "transparent"
                    border.width: model.accepted ? 1 : 0
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 10

                    // Type badge
                    Rectangle {
                        width:  70; height: 20; radius: 3
                        color: "transparent"
                        border.color: _typeColor(model.diffType)
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text:  _typeBadge(model.diffType)
                            color: _typeColor(model.diffType)
                            font { pixelSize: 9; bold: true }
                        }
                    }

                    // Staff badge
                    Text {
                        text:  "Staff " + model.staffIndex
                        color: "#585b70"
                        font.pixelSize: 11
                    }

                    // Description
                    Text {
                        text:  model.description
                        color: "#cdd6f4"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Accept toggle
                    Button {
                        id:    acceptBtn
                        text:  model.accepted ? "✓ Accepted" : "Accept"
                        width: 80; height: 28
                        contentItem: Text {
                            text:  parent.text
                            color: model.accepted ? "#1e1e2e" : "#a6e3a1"
                            font { pixelSize: 11; bold: model.accepted }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 4
                            color:  model.accepted
                                    ? (parent.pressed ? "#4dab64" : "#a6e3a1")
                                    : (parent.pressed ? "#313244" : "transparent")
                            border.color: "#a6e3a1"
                            border.width: 1
                        }
                        onClicked: _setAccepted(model.diffIndex, !model.accepted)
                    }

                    // Reject toggle
                    Button {
                        text:  model.accepted ? "Reject" : "✗ Rejected"
                        width: 80; height: 28
                        contentItem: Text {
                            text:  parent.text
                            color: !model.accepted ? "#1e1e2e" : "#f38ba8"
                            font { pixelSize: 11; bold: !model.accepted }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 4
                            color:  !model.accepted
                                    ? (parent.pressed ? "#b55a6a" : "#f38ba8")
                                    : (parent.pressed ? "#313244" : "transparent")
                            border.color: "#f38ba8"
                            border.width: 1
                        }
                        onClicked: _setAccepted(model.diffIndex, false)
                    }
                }
            }
        }

        Rectangle { height: 1; color: "#313244"; Layout.fillWidth: true; visible: diffModel.count > 0 }

        // ---- Bottom action bar ----
        RowLayout {
            Layout.fillWidth: true
            visible: diffModel.count > 0
            spacing: 10

            // Counter badge
            Rectangle {
                color:  "#313244"; radius: 6
                width:  counterText.implicitWidth + 16; height: 28
                Text {
                    id:    counterText
                    anchors.centerIn: parent
                    text:  diffModel.count + " change" + (diffModel.count !== 1 ? "s" : "")
                         + " | " + root._acceptedCount + " accepted"
                    color: "#a6adc8"; font.pixelSize: 12
                }
            }

            Item { Layout.fillWidth: true }

            // Accept All
            Button {
                text:  "Accept All"
                contentItem: Text { text: parent.text; color: "#1e1e2e"; font { pixelSize: 12; bold: true }; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 5; color: parent.pressed ? "#4dab64" : parent.hovered ? "#86d4a0" : "#a6e3a1"; implicitWidth: 90; implicitHeight: 30 }
                onClicked: _acceptAll()
            }

            // Reject All
            Button {
                text:  "Reject All"
                contentItem: Text { text: parent.text; color: "#1e1e2e"; font { pixelSize: 12; bold: true }; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 5; color: parent.pressed ? "#b55a6a" : parent.hovered ? "#e07080" : "#f38ba8"; implicitWidth: 90; implicitHeight: 30 }
                onClicked: _rejectAll()
            }

            // Apply Accepted
            Button {
                text:    "Apply Accepted Changes"
                enabled: root._acceptedCount > 0
                contentItem: Text {
                    text:  parent.text
                    color: parent.enabled ? "#1e1e2e" : "#585b70"
                    font { pixelSize: 12; bold: true }
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 5
                    color:  !parent.enabled  ? "#313244"
                           : parent.pressed  ? "#5296e4"
                           : parent.hovered  ? "#74aaee"
                           :                   "#89b4fa"
                    implicitWidth:  180; implicitHeight: 30
                }
                onClicked: _applyAccepted()
            }
        }
    }
}
