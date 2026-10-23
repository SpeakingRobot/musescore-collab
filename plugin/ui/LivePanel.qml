// LivePanel.qml
// MuseCollab v2 — Real-time live broadcasting & watching panel.
// Theme: Catppuccin Mocha.

import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

Rectangle {
    id: root

    // -----------------------------------------------------------------------
    // Public properties
    // -----------------------------------------------------------------------
    property bool   isHost:           false
    property string hostUsername:     ""
    property int    watcherCount:     0
    property string sessionId:        ""
    property string lastSnapshotTime: ""
    property var    lastSnapshot:     null

    property bool   autoBroadcast:    false
    property int    autoBroadcastInterval: 5000

    // -----------------------------------------------------------------------
    // Signals
    // -----------------------------------------------------------------------
    signal broadcastScore()
    signal stopSession()
    signal leaveSession()
    signal viewDiffRequested(var snapshot)
    signal suggestionAccepted(var suggestion)
    signal suggestionRejected(var suggestion)
    signal sendSuggestion(int measureNumber, string fromNote, string toNote, string desc)

    // -----------------------------------------------------------------------
    // Internal models
    // -----------------------------------------------------------------------
    ListModel { id: suggestionsModel }

    function addSuggestion(suggestion) {
        suggestionsModel.append({
            from:          suggestion.from || "Collaborator",
            measureNumber: suggestion.measureNumber || 1,
            fromNote:      suggestion.fromNote || "",
            toNote:        suggestion.toNote || "",
            description:   suggestion.description || ""
        })
    }

    function clearSuggestions() {
        suggestionsModel.clear()
    }

    // Auto-broadcast timer
    Timer {
        id: autoBroadcastTimer
        interval: root.autoBroadcastInterval
        running:  root.autoBroadcast && root.isHost
        repeat:   true
        onTriggered: root.broadcastScore()
    }

    // -----------------------------------------------------------------------
    // Appearance
    // -----------------------------------------------------------------------
    color:  "#1e1e2e"
    radius: 8

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // ---- Live Header Banner ----
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color:  root.isHost ? "#2b1a20" : "#1e2838"
            radius: 8
            border.color: root.isHost ? "#f38ba8" : "#89b4fa"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                // Pulsing live indicator
                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: root.isHost ? "#f38ba8" : "#a6e3a1"

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: true
                        PropertyAnimation { to: 0.3; duration: 800 }
                        PropertyAnimation { to: 1.0; duration: 800 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.isHost ? "🔴 LIVE BROADCASTING" : "🔴 WATCHING: " + root.hostUsername
                        color: "#cdd6f4"
                        font { pixelSize: 13; bold: true }
                    }
                    Text {
                        text: {
                            var t = root.lastSnapshotTime ? "Last update: " + root.lastSnapshotTime : "Waiting for updates..."
                            return t + " • " + root.watcherCount + " watching"
                        }
                        color: "#a6adc8"
                        font.pixelSize: 11
                    }
                }

                Button {
                    text: root.isHost ? "Stop" : "Leave"
                    implicitWidth: 60; implicitHeight: 28
                    contentItem: Text {
                        text: parent.text; color: "#f38ba8"; font { pixelSize: 11; bold: true }
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle { radius: 4; color: parent.pressed ? "#45475a" : "#313244" }
                    onClicked: {
                        if (root.isHost) root.stopSession()
                        else root.leaveSession()
                    }
                }
            }
        }

        // ===================================================================
        // HOST CONTROLS
        // ===================================================================
        ColumnLayout {
            visible: root.isHost
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // Broadcast button
            Button {
                id: sendScoreBtn
                Layout.fillWidth: true
                height: 40
                text: "📤 Broadcast Current Score Now"
                contentItem: Text {
                    text: parent.text; color: "#1e1e2e"; font { pixelSize: 13; bold: true }
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 6
                    color: sendScoreBtn.pressed ? "#5296e4" : "#89b4fa"
                }
                onClicked: root.broadcastScore()
            }

            // Auto-broadcast toggle
            Rectangle {
                Layout.fillWidth: true
                height: 38
                color:  "#181825"
                radius: 6

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        text: "Auto-broadcast every 5 seconds"
                        color: "#cdd6f4"
                        font.pixelSize: 12
                        Layout.fillWidth: true
                    }

                    Switch {
                        id: autoSwitch
                        checked: root.autoBroadcast
                        onToggled: root.autoBroadcast = checked
                    }
                }
            }

            // Incoming Suggestions Section
            Text {
                text: "Collaborator Suggestions (" + suggestionsModel.count + ")"
                color: "#cba6f7"
                font { pixelSize: 12; bold: true }
                Layout.topMargin: 4
            }

            Rectangle {
                Layout.fillWidth:  true
                Layout.fillHeight: true
                color:  "#181825"
                radius: 6
                clip:   true

                ListView {
                    id: suggListView
                    anchors.fill: parent
                    anchors.margins: 6
                    model: suggestionsModel
                    spacing: 6

                    Text {
                        visible: suggestionsModel.count === 0
                        anchors.centerIn: parent
                        text: "No suggestions yet from watchers."
                        color: "#585b70"
                        font.pixelSize: 12
                    }

                    delegate: Rectangle {
                        width: suggListView.width
                        height: 52
                        color:  "#313244"
                        radius: 6

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "👤 " + model.from + " • Measure " + model.measureNumber
                                    color: "#cdd6f4"
                                    font { pixelSize: 12; bold: true }
                                }
                                Text {
                                    text: model.description || (model.fromNote + " → " + model.toNote)
                                    color: "#a6e3a1"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            Button {
                                text: "Accept"
                                implicitWidth: 54; implicitHeight: 26
                                contentItem: Text { text: parent.text; color: "#1e1e2e"; font { pixelSize: 11; bold: true }; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 4; color: "#a6e3a1" }
                                onClicked: {
                                    root.suggestionAccepted({
                                        from: model.from,
                                        measureNumber: model.measureNumber,
                                        fromNote: model.fromNote,
                                        toNote: model.toNote
                                    })
                                    suggestionsModel.remove(index)
                                }
                            }

                            Button {
                                text: "✕"
                                implicitWidth: 26; implicitHeight: 26
                                contentItem: Text { text: parent.text; color: "#f38ba8"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 4; color: "#45475a" }
                                onClicked: {
                                    root.suggestionRejected({
                                        from: model.from,
                                        measureNumber: model.measureNumber
                                    })
                                    suggestionsModel.remove(index)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ===================================================================
        // WATCHER CONTROLS
        // ===================================================================
        ColumnLayout {
            visible: !root.isHost
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // View snapshot in Diff Viewer button
            Button {
                id: viewDiffBtn
                Layout.fillWidth: true
                height: 38
                enabled: root.lastSnapshot !== null
                text: "🔀 Compare Live Snapshot with My Score"
                contentItem: Text {
                    text: parent.text; color: viewDiffBtn.enabled ? "#1e1e2e" : "#585b70"
                    font { pixelSize: 12; bold: true }
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 6
                    color: viewDiffBtn.enabled ? "#cba6f7" : "#313244"
                }
                onClicked: root.viewDiffRequested(root.lastSnapshot)
            }

            // Suggest Edit Form
            Rectangle {
                Layout.fillWidth: true
                height: formCol.implicitHeight + 20
                color:  "#181825"
                radius: 8

                ColumnLayout {
                    id: formCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "💡 Suggest an Edit to Host"
                        color: "#89b4fa"
                        font { pixelSize: 12; bold: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text { text: "Bar #"; color: "#a6adc8"; font.pixelSize: 12 }
                        TextField {
                            id: barNumField
                            Layout.preferredWidth: 44
                            text: "1"
                            color: "#cdd6f4"
                            font.pixelSize: 12
                            background: Rectangle { color: "#313244"; radius: 4; border.color: "#45475a" }
                        }

                        Text { text: "From"; color: "#a6adc8"; font.pixelSize: 12 }
                        TextField {
                            id: fromNoteField
                            Layout.fillWidth: true
                            placeholderText: "C4"
                            color: "#cdd6f4"
                            font.pixelSize: 12
                            background: Rectangle { color: "#313244"; radius: 4; border.color: "#45475a" }
                        }

                        Text { text: "→"; color: "#a6adc8"; font.pixelSize: 12 }
                        TextField {
                            id: toNoteField
                            Layout.fillWidth: true
                            placeholderText: "D4"
                            color: "#cdd6f4"
                            font.pixelSize: 12
                            background: Rectangle { color: "#313244"; radius: 4; border.color: "#45475a" }
                        }
                    }

                    Button {
                        text: "Send Suggestion"
                        Layout.fillWidth: true
                        height: 32
                        contentItem: Text {
                            text: parent.text; color: "#1e1e2e"; font { pixelSize: 12; bold: true }
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle { radius: 5; color: "#89b4fa" }
                        onClicked: {
                            var bNum = parseInt(barNumField.text, 10) || 1
                            var fN   = fromNoteField.text.trim()
                            var tN   = toNoteField.text.trim()
                            if (fN || tN) {
                                root.sendSuggestion(bNum, fN, tN, "Bar " + bNum + ": " + fN + " → " + tN)
                                fromNoteField.text = ""
                                toNoteField.text   = ""
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
