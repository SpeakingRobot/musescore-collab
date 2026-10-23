// MeasurePicker.qml
// MuseCollab v2 — Measure cherry-pick panel for importing bars into main score.
// Theme: Catppuccin Mocha.

import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

Rectangle {
    id: root

    // -----------------------------------------------------------------------
    // Public properties
    // -----------------------------------------------------------------------
    property var    measureDiffs: []     // [{ measureNumber, status, summaryA, summaryB, eventDiffs }]
    property string baseTitle:    "main"
    property string sourceTitle:  "collaborator/main"

    // -----------------------------------------------------------------------
    // Signals
    // -----------------------------------------------------------------------
    signal importRequested(var measureNumbers)
    signal cancelled()

    // -----------------------------------------------------------------------
    // Internal state
    // -----------------------------------------------------------------------
    // Set of selected measure numbers (measureNumber -> bool)
    property var _selectedMap: ({})
    property int _selectedCount: 0

    onMeasureDiffsChanged: {
        _resetSelection()
    }

    function _resetSelection() {
        var m = {}
        var count = 0
        if (measureDiffs && measureDiffs.length > 0) {
            for (var i = 0; i < measureDiffs.length; i++) {
                var mNum = measureDiffs[i].measureNumber
                // By default, select modified and added bars
                if (measureDiffs[i].status !== "removed") {
                    m[mNum] = true
                    count++
                } else {
                    m[mNum] = false
                }
            }
        }
        _selectedMap = m
        _selectedCount = count
        measureListModel.clear()
        if (measureDiffs && measureDiffs.length > 0) {
            for (var j = 0; j < measureDiffs.length; j++) {
                var d = measureDiffs[j]
                measureListModel.append({
                    measureNumber: d.measureNumber,
                    status:        d.status || "modified",
                    summaryA:      d.summaryA || "",
                    summaryB:      d.summaryB || "",
                    selected:      !!m[d.measureNumber]
                })
            }
        }
    }

    function selectAll() {
        var m = {}
        for (var i = 0; i < measureListModel.count; i++) {
            var mNum = measureListModel.get(i).measureNumber
            m[mNum] = true
            measureListModel.setProperty(i, "selected", true)
        }
        _selectedMap = m
        _selectedCount = measureListModel.count
    }

    function clearAll() {
        var m = {}
        for (var i = 0; i < measureListModel.count; i++) {
            var mNum = measureListModel.get(i).measureNumber
            m[mNum] = false
            measureListModel.setProperty(i, "selected", false)
        }
        _selectedMap = m
        _selectedCount = 0
    }

    function toggleMeasure(idx) {
        var item = measureListModel.get(idx)
        var next = !item.selected
        measureListModel.setProperty(idx, "selected", next)

        var m = Object.assign({}, _selectedMap)
        m[item.measureNumber] = next
        _selectedMap = m

        var count = 0
        for (var k in m) {
            if (m[k]) count++
        }
        _selectedCount = count
    }

    ListModel { id: measureListModel }

    // -----------------------------------------------------------------------
    // Appearance
    // -----------------------------------------------------------------------
    color:  "#1e1e2e"
    radius: 8

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // ---- Header ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "📐 Cherry-pick Measures"
                    color: "#cdd6f4"
                    font { pixelSize: 16; bold: true }
                }
                Text {
                    text: "From " + root.sourceTitle + " → " + root.baseTitle
                    color: "#89b4fa"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Button {
                text: "✕ Close"
                implicitWidth: 64; implicitHeight: 28
                contentItem: Text {
                    text: parent.text; color: "#a6adc8"; font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { radius: 4; color: parent.pressed ? "#45475a" : "#313244" }
                onClicked: root.cancelled()
            }
        }

        // ---- Selection actions bar ----
        Rectangle {
            Layout.fillWidth: true
            height: 36
            color:  "#181825"
            radius: 6

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Button {
                    text: "Select All"
                    implicitHeight: 24
                    contentItem: Text { text: parent.text; color: "#89b4fa"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { color: "transparent" }
                    onClicked: root.selectAll()
                }

                Text { text: "•"; color: "#585b70" }

                Button {
                    text: "Clear All"
                    implicitHeight: 24
                    contentItem: Text { text: parent.text; color: "#a6adc8"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { color: "transparent" }
                    onClicked: root.clearAll()
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root._selectedCount + " bar(s) selected"
                    color: root._selectedCount > 0 ? "#a6e3a1" : "#585b70"
                    font { pixelSize: 11; bold: true }
                }
            }
        }

        // ---- Empty state ----
        Text {
            visible: measureListModel.count === 0
            text: "No differences found between these two branches."
            color: "#a6adc8"
            font.pixelSize: 13
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 40
        }

        // ---- Measures ListView ----
        ListView {
            id: measureListView
            Layout.fillWidth:  true
            Layout.fillHeight: true
            clip: true
            model: measureListModel
            spacing: 6

            delegate: Rectangle {
                width:  measureListView.width
                height: 56
                radius: 6

                // Status colors
                property color statusColor: {
                    if (model.status === "added")    return "#a6e3a1"
                    if (model.status === "removed")  return "#f38ba8"
                    return "#f9e2af" // modified
                }

                color: model.selected
                       ? (model.status === "added" ? "#1e3325" : model.status === "removed" ? "#331e25" : "#333020")
                       : "#181825"

                border.color: model.selected ? statusColor : "#313244"
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.toggleMeasure(index)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    // Checkbox indicator
                    Rectangle {
                        width: 18; height: 18; radius: 4
                        color: model.selected ? statusColor : "transparent"
                        border.color: statusColor
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: "#1e1e2e"
                            font { pixelSize: 12; bold: true }
                            visible: model.selected
                        }
                    }

                    // Measure details
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            spacing: 8
                            Text {
                                text: "Measure " + model.measureNumber
                                color: "#cdd6f4"
                                font { pixelSize: 13; bold: true }
                            }

                            // Status badge
                            Rectangle {
                                radius: 3
                                height: 16
                                width: badgeText.implicitWidth + 8
                                color: parent.parent.parent.parent.statusColor

                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: {
                                        if (model.status === "added")   return "New"
                                        if (model.status === "removed") return "Deleted"
                                        return "Modified"
                                    }
                                    color: "#1e1e2e"
                                    font { pixelSize: 9; bold: true }
                                }
                            }
                        }

                        // Pitch summary
                        Text {
                            Layout.fillWidth: true
                            text: {
                                if (model.status === "added") return "Added: " + model.summaryB
                                if (model.status === "removed") return "Removed: " + model.summaryA
                                return model.summaryA + " → " + model.summaryB
                            }
                            color: "#a6adc8"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // ---- Footer actions ----
        Rectangle {
            Layout.fillWidth: true
            height: 48
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                spacing: 10

                Button {
                    text: "Cancel"
                    Layout.preferredWidth: 80
                    Layout.fillHeight: true
                    contentItem: Text {
                        text: parent.text; color: "#cdd6f4"; font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle { radius: 6; color: parent.pressed ? "#313244" : "#45475a" }
                    onClicked: root.cancelled()
                }

                Button {
                    id: importBtn
                    enabled: root._selectedCount > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: "🎵 Import " + root._selectedCount + " Selected Bar(s)"

                    contentItem: Text {
                        text: parent.text
                        color: importBtn.enabled ? "#1e1e2e" : "#585b70"
                        font { pixelSize: 13; bold: true }
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 6
                        color: importBtn.enabled
                               ? (parent.pressed ? "#4dab64" : "#a6e3a1")
                               : "#313244"
                    }
                    onClicked: {
                        var nums = []
                        for (var i = 0; i < measureListModel.count; i++) {
                            var item = measureListModel.get(i)
                            if (item.selected) {
                                nums.push(item.measureNumber)
                            }
                        }
                        root.importRequested(nums)
                    }
                }
            }
        }
    }
}
