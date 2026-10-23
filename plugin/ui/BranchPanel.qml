// BranchPanel.qml
// MuseCollab v2 — Branch switcher, collaborators, live session controls.
// Theme: Catppuccin Mocha.

import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

Rectangle {
    id: root

    // -----------------------------------------------------------------------
    // Public properties
    // -----------------------------------------------------------------------
    property string serverUrl:     ""
    property string token:         ""
    property string project:       ""
    property string currentBranch: "main"
    property string myBranch:      "main"
    property string displayName:   ""
    property string inviteCode:    ""
    property string liveSessionId: ""
    property bool   isLive:        false
    property string watchingSessionId: ""

    // Ahead / behind main counter
    property int aheadCount:  0
    property int behindCount: 0

    // -----------------------------------------------------------------------
    // Signals
    // -----------------------------------------------------------------------
    signal pushRequested(string message)
    signal pullRequested(string branch)
    signal diffRequested(string theirBranch)
    signal viewRequested(string branch)
    signal branchCreated(string name)
    signal measureDiffRequested(string branch)
    signal goLiveRequested()
    signal stopLiveRequested()
    signal watchLiveRequested(string sessionId)

    // -----------------------------------------------------------------------
    // Internal models / state
    // -----------------------------------------------------------------------
    property var _branches:      []
    property var _collaborators: []
    property bool _loading:      false
    property string _errorText:  ""

    ListModel { id: branchModel }
    ListModel { id: collabModel }

    // -----------------------------------------------------------------------
    // Appearance
    // -----------------------------------------------------------------------
    color:  "#1e1e2e"
    radius: 8

    // -----------------------------------------------------------------------
    // Init & data loading
    // -----------------------------------------------------------------------
    Component.onCompleted: {
        _loadBranches()
        _loadCollaborators()
    }

    // React to token / project changes
    onTokenChanged:   { _loadBranches(); _loadCollaborators() }
    onProjectChanged: { _loadBranches(); _loadCollaborators() }

    // -----------------------------------------------------------------------
    // Public refresh function (called by main plugin on reconnect)
    // -----------------------------------------------------------------------
    function refreshCollaborators() {
        _loadCollaborators()
    }

    // -----------------------------------------------------------------------
    // Network helpers
    // -----------------------------------------------------------------------
    function _apiGet(path, cb) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", root.serverUrl.replace(/\/$/, "") + path, true)
        xhr.setRequestHeader("Authorization", "Bearer " + root.token)
        xhr.timeout = 15000
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var data = null
            try { data = JSON.parse(xhr.responseText) } catch (e) {}
            if (xhr.status >= 200 && xhr.status < 300) { cb(null, data) }
            else { cb((data && (data.message || data.error)) || ("HTTP " + xhr.status), null) }
        }
        xhr.onerror   = function () { cb("Network error", null) }
        xhr.ontimeout = function () { cb("Timeout", null) }
        xhr.send()
    }

    function _apiPost(path, body, cb) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", root.serverUrl.replace(/\/$/, "") + path, true)
        xhr.setRequestHeader("Authorization", "Bearer " + root.token)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 15000
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var data = null
            try { data = JSON.parse(xhr.responseText) } catch (e) {}
            if (xhr.status >= 200 && xhr.status < 300) { cb(null, data) }
            else { cb((data && (data.message || data.error)) || ("HTTP " + xhr.status), null) }
        }
        xhr.onerror   = function () { cb("Network error", null) }
        xhr.ontimeout = function () { cb("Timeout", null) }
        xhr.send(JSON.stringify(body))
    }

    function _loadBranches() {
        if (!root.serverUrl || !root.token || !root.project) return
        _apiGet("/api/projects/" + encodeURIComponent(root.project) + "/branches",
            function (err, data) {
                branchModel.clear()
                if (err || !data) return
                var arr = Array.isArray(data) ? data : (data.data ? data.data : (data.branches || []))
                root._branches = arr
                for (var i = 0; i < arr.length; i++) {
                    branchModel.append({ branchName: arr[i].name || arr[i] })
                    if ((arr[i].name || arr[i]) === root.currentBranch) {
                        root.aheadCount  = arr[i].aheadBy  || 0
                        root.behindCount = arr[i].behindBy || 0
                    }
                }
                for (var j = 0; j < branchModel.count; j++) {
                    if (branchModel.get(j).branchName === root.currentBranch) {
                        branchCombo.currentIndex = j
                        break
                    }
                }
            }
        )
    }

    function _loadCollaborators() {
        if (!root.serverUrl || !root.token || !root.project) return
        _apiGet("/api/projects/" + encodeURIComponent(root.project) + "/collaborators",
            function (err, data) {
                collabModel.clear()
                if (err || !data) return
                var arr = Array.isArray(data) ? data : (data.data ? data.data : (data.collaborators || []))
                root._collaborators = arr
                for (var i = 0; i < arr.length; i++) {
                    var c = arr[i]
                    var pushTime = c.lastPushAt || c.lastPushTime
                    collabModel.append({
                        avatarInitial:  (c.displayName || c.username || "?")[0].toUpperCase(),
                        displayName:    c.displayName  || c.username || "unknown",
                        username:       c.username     || "",
                        branch:         c.branchName   || c.branch   || "main",
                        lastPushTime:   pushTime ? _formatTime(pushTime) : "—",
                        isLive:         c.isLive       || false,
                        liveSessionId:  c.liveSessionId || ""
                    })
                }
            }
        )
    }

    function _formatTime(isoString) {
        try {
            var d = new Date(isoString)
            return d.toLocaleDateString() + " " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
        } catch (e) {
            return isoString
        }
    }

    function _avatarColor(name) {
        var palette = ["#89b4fa", "#a6e3a1", "#f9e2af", "#f38ba8", "#cba6f7", "#89dceb", "#fab387"]
        if (!name || name.length === 0) return palette[0]
        var hash = 0
        for (var i = 0; i < name.length; i++) {
            hash = (hash * 31 + name.charCodeAt(i)) & 0xffffffff
        }
        return palette[Math.abs(hash) % palette.length]
    }

    // -----------------------------------------------------------------------
    // Main layout
    // -----------------------------------------------------------------------
    ColumnLayout {
        anchors { fill: parent; margins: 14 }
        spacing: 10

        // ---- Header row ----
        RowLayout {
            Layout.fillWidth: true

            Text {
                text:  "🌿  Branches"
                font { pixelSize: 20; bold: true }
                color: "#cdd6f4"
            }

            Item { Layout.fillWidth: true }

            // Ahead/behind badge
            Rectangle {
                visible: root.aheadCount > 0 || root.behindCount > 0
                color:   "#313244"
                radius:  10
                width:   aheadBehindLabel.implicitWidth + 16
                height:  22

                Text {
                    id: aheadBehindLabel
                    anchors.centerIn: parent
                    text: (root.aheadCount  > 0 ? "↑" + root.aheadCount  + " " : "")
                        + (root.behindCount > 0 ? "↓" + root.behindCount : "")
                    color: "#f9e2af"
                    font.pixelSize: 11
                }
            }

            // Refresh
            Button {
                text:   "↻"
                width:  30; height: 30
                contentItem: Text {
                    text:  parent.text
                    color: "#89b4fa"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
                }
                background: Rectangle {
                    color:  parent.pressed ? "#313244" : "transparent"
                    radius: 4
                }
                onClicked: { _loadBranches(); _loadCollaborators() }
            }
        }

        // ---- Invite code display (project owner) ----
        Rectangle {
            Layout.fillWidth: true
            height: inviteRow.implicitHeight + 14
            color:  "#1a1a2e"
            radius: 6
            border.color: "#45475a"
            border.width: 1
            visible: root.inviteCode.length > 0

            RowLayout {
                id: inviteRow
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 8

                Text {
                    text:  "🔑 Project Code:"
                    color: "#a6adc8"
                    font.pixelSize: 12
                }
                Text {
                    text:  root.inviteCode
                    color: "#cba6f7"
                    font { pixelSize: 14; bold: true; family: "monospace" }
                    Layout.fillWidth: true
                }
                Button {
                    text: "Copy"
                    implicitWidth: 48; implicitHeight: 24
                    contentItem: Text {
                        text: parent.text; color: "#1e1e2e"
                        font { pixelSize: 10; bold: true }
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 4
                        color: parent.pressed ? "#9b6fe8" : "#cba6f7"
                    }
                    onClicked: {
                        inviteClipHelper.text = root.inviteCode
                        inviteClipHelper.selectAll()
                        inviteClipHelper.copy()
                    }
                }
            }
        }

        Rectangle { height: 1; color: "#313244"; Layout.fillWidth: true }

        // ---- Branch ComboBox row ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text { text: "Branch:"; color: "#a6adc8"; font.pixelSize: 13 }

            ComboBox {
                id:    branchCombo
                model: branchModel
                textRole: "branchName"
                Layout.fillWidth: true
                font.pixelSize:   13

                contentItem: Text {
                    leftPadding: 8
                    text:        branchCombo.displayText
                    color:       "#cdd6f4"
                    font:        branchCombo.font
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color:        "#313244"
                    radius:       4
                    border.color: branchCombo.activeFocus ? "#89b4fa" : "#45475a"
                    border.width: 1
                }
                popup: Popup {
                    y:      branchCombo.height
                    width:  branchCombo.width
                    padding: 1
                    contentItem: ListView {
                        clip: true
                        implicitHeight: Math.min(contentHeight, 200)
                        model: branchCombo.popup.visible ? branchCombo.delegateModel : null
                        ScrollIndicator.vertical: ScrollIndicator {}
                    }
                    background: Rectangle { color: "#313244"; radius: 4; border.color: "#45475a" }
                }
                delegate: ItemDelegate {
                    width:  branchCombo.width
                    contentItem: Text {
                        text:  modelData || model.branchName || ""
                        color: highlighted ? "#89b4fa" : "#cdd6f4"
                        font.pixelSize: 13
                    }
                    highlighted: branchCombo.highlightedIndex === index
                    background: Rectangle { color: highlighted ? "#45475a" : "transparent" }
                }
                onActivated: {
                    var sel = branchModel.get(currentIndex) ? branchModel.get(currentIndex).branchName : ""
                    if (sel && sel !== root.currentBranch) {
                        root.currentBranch = sel
                        root._loadBranches()
                    }
                }
            }
        }

        // ---- Action buttons ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text:    "📤 Push"
                enabled: !root._loading
                Layout.fillWidth: true
                contentItem: Text {
                    text:  parent.text; color: "#1e1e2e"; font.pixelSize: 12; font.bold: true
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { radius: 5; color: parent.pressed ? "#5296e4" : parent.hovered ? "#74aaee" : "#89b4fa" }
                onClicked: pushDialog.open()
            }

            Button {
                text:    "📥 Pull"
                enabled: !root._loading
                Layout.fillWidth: true
                contentItem: Text {
                    text:  parent.text; color: "#cdd6f4"; font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { radius: 5; color: parent.pressed ? "#2a2a3e" : parent.hovered ? "#313244" : "#45475a"; border.color: "#89b4fa"; border.width: 1 }
                onClicked: root.pullRequested(root.currentBranch)
            }

            Button {
                text:    "➕ Branch"
                enabled: !root._loading
                Layout.fillWidth: true
                contentItem: Text {
                    text:  parent.text; color: "#cdd6f4"; font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { radius: 5; color: parent.pressed ? "#2a2a3e" : parent.hovered ? "#313244" : "#45475a"; border.color: "#a6e3a1"; border.width: 1 }
                onClicked: newBranchDialog.open()
            }
        }

        Rectangle { height: 1; color: "#313244"; Layout.fillWidth: true }

        // ---- Collaborators header ----
        Text {
            text:  "👥  Collaborators"
            font { pixelSize: 15; bold: true }
            color: "#cdd6f4"
        }

        // ---- Column headers ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Text { text: "User";       color: "#585b70"; font.pixelSize: 11; Layout.preferredWidth: 110 }
            Text { text: "Branch";     color: "#585b70"; font.pixelSize: 11; Layout.preferredWidth: 80  }
            Text { text: "Last Push";  color: "#585b70"; font.pixelSize: 11; Layout.fillWidth: true     }
            Text { text: "Actions";    color: "#585b70"; font.pixelSize: 11; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignRight }
        }

        // ---- Collaborator list ----
        ListView {
            id:    collabList
            model: collabModel
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip:  true
            spacing: 4

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: collabRow
                width:  collabList.width
                height: model.isLive ? 56 : 50
                color:  index % 2 === 0 ? "#181825" : "#1e1e2e"
                radius: 4

                RowLayout {
                    anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                    spacing: 6

                    // Avatar circle
                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: _avatarColor(model.displayName)

                        Text {
                            anchors.centerIn: parent
                            text:  model.avatarInitial || "?"
                            color: "#1e1e2e"
                            font { pixelSize: 14; bold: true }
                        }
                    }

                    // Name column
                    ColumnLayout {
                        spacing: 1
                        Layout.preferredWidth: 94

                        Text {
                            text:  model.displayName || "—"
                            color: "#cdd6f4"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text:  "@" + (model.username || "")
                            color: "#585b70"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // Branch badge
                    Rectangle {
                        color:  "#313244"; radius: 8
                        width:  Math.min(branchBadge.implicitWidth + 12, 80)
                        height: 20

                        Text {
                            id:    branchBadge
                            anchors.centerIn: parent
                            text:  model.branch || "main"
                            color: "#89b4fa"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Last push
                    Text {
                        text:  model.lastPushTime || "—"
                        color: "#585b70"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Live indicator & buttons
                    RowLayout {
                        spacing: 4
                        Layout.preferredWidth: 100

                        // Pulsing live dot
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: "#f38ba8"
                            visible: model.isLive

                            SequentialAnimation on opacity {
                                running: model.isLive
                                loops:   Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 700 }
                                NumberAnimation { to: 1.0; duration: 700 }
                            }
                        }

                        // When live: show Watch Live button
                        Button {
                            visible: model.isLive
                            text:    "Watch"
                            implicitWidth: 52; implicitHeight: 26
                            contentItem: Text {
                                text: parent.text; color: "#1e1e2e"
                                font { pixelSize: 10; bold: true }
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { radius: 3; color: parent.pressed ? "#c4534a" : "#f38ba8" }
                            onClicked: root.watchLiveRequested(model.liveSessionId)
                        }

                        // When not live: show Measure Diff + View buttons
                        Button {
                            visible: !model.isLive
                            text:    "Δ Diff"
                            implicitWidth: 44; implicitHeight: 26
                            contentItem: Text {
                                text: parent.text; color: "#f9e2af"; font.pixelSize: 10
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: parent.pressed ? "#313244" : "transparent"; radius: 3; border.color: "#f9e2af"; border.width: 1 }
                            onClicked: root.measureDiffRequested(model.branch)
                        }

                        Button {
                            visible: !model.isLive
                            text:    "View"
                            implicitWidth: 40; implicitHeight: 26
                            contentItem: Text {
                                text: parent.text; color: "#89b4fa"; font.pixelSize: 10
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: parent.pressed ? "#313244" : "transparent"; radius: 3; border.color: "#89b4fa"; border.width: 1 }
                            onClicked: root.viewRequested(model.branch)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: collabModel.count === 0 && !root._loading
                text:    "No collaborators yet"
                color:   "#585b70"
                font.pixelSize: 13
            }
        }

        // ---- Live Session section ----
        Rectangle {
            Layout.fillWidth: true
            height: liveCol.implicitHeight + 16
            color:  "#1a1a2e"
            radius: 6
            border.color: root.isLive ? "#f38ba8" : "#45475a"
            border.width: root.isLive ? 2 : 1

            ColumnLayout {
                id: liveCol
                anchors { fill: parent; margins: 8 }
                spacing: 8

                RowLayout {
                    spacing: 6

                    // Pulsing dot when live
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: "#f38ba8"
                        visible: root.isLive
                        SequentialAnimation on opacity {
                            running: root.isLive
                            loops:   Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 700 }
                            NumberAnimation { to: 1.0; duration: 700 }
                        }
                    }

                    Text {
                        text:  root.isLive ? "YOU ARE LIVE" : "LIVE SESSION"
                        color: root.isLive ? "#f38ba8" : "#a6adc8"
                        font { pixelSize: 12; bold: true }
                    }
                }

                RowLayout {
                    spacing: 8

                    // Go Live / Stop Live button
                    Button {
                        text:    root.isLive ? "⏹ Stop Live" : "🔴 Go Live"
                        Layout.fillWidth: true
                        contentItem: Text {
                            text:  parent.text
                            color: root.isLive ? "#cdd6f4" : "#1e1e2e"
                            font { pixelSize: 12; bold: true }
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 5
                            color: {
                                if (root.isLive) {
                                    return parent.pressed ? "#2a2a3e" : "#45475a"
                                }
                                return parent.pressed ? "#c4534a" : "#f38ba8"
                            }
                        }
                        onClicked: {
                            if (root.isLive) {
                                root.stopLiveRequested()
                            } else {
                                root.goLiveRequested()
                            }
                        }
                    }

                    // Join Session button (only when not already live)
                    Button {
                        text:    "👁 Join Session"
                        visible: !root.isLive
                        Layout.fillWidth: true
                        contentItem: Text {
                            text:  parent.text; color: "#cdd6f4"; font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 5
                            color: parent.pressed ? "#2a2a3e" : parent.hovered ? "#313244" : "#45475a"
                            border.color: "#89b4fa"; border.width: 1
                        }
                        onClicked: {
                            // Reload collaborators to find active sessions; UI handles selection
                            _loadCollaborators()
                        }
                    }
                }
            }
        }

        // ---- Error banner ----
        Rectangle {
            Layout.fillWidth: true
            height:  errLabel.implicitHeight + 10
            color:   "#2a1a1a"
            radius:  4
            visible: root._errorText.length > 0
            Text {
                id:      errLabel
                anchors { fill: parent; margins: 5 }
                text:    root._errorText
                color:   "#f38ba8"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }
    }

    // Hidden clipboard helper
    TextEdit { id: inviteClipHelper; visible: false; text: "" }

    // -----------------------------------------------------------------------
    // Push dialog
    // -----------------------------------------------------------------------
    Dialog {
        id:      pushDialog
        title:   "Push Changes"
        modal:   true
        anchors.centerIn: parent
        width:   320

        background: Rectangle { color: "#313244"; radius: 8; border.color: "#45475a" }
        header: Rectangle {
            color: "#313244"; radius: 8; height: 44
            Text { anchors.centerIn: parent; text: "📤  Push Changes"; color: "#cdd6f4"; font { pixelSize: 15; bold: true } }
        }

        contentItem: ColumnLayout {
            spacing: 12
            width: pushDialog.availableWidth

            Text { text: "Commit message:"; color: "#a6adc8"; font.pixelSize: 13 }

            TextField {
                id:    commitMsgField
                Layout.fillWidth: true
                placeholderText:  "Describe your changes…"
                color:            "#cdd6f4"
                placeholderTextColor: "#585b70"
                font.pixelSize:   13
                background: Rectangle { color: "#1e1e2e"; radius: 4; border.color: "#89b4fa"; border.width: 1 }
                leftPadding: 8; rightPadding: 8
            }

            Text { text: "Branch: " + root.currentBranch; color: "#585b70"; font.pixelSize: 12 }
        }

        footer: DialogButtonBox {
            background: Rectangle { color: "transparent" }
            Button {
                text: "Push"
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                contentItem: Text { text: parent.text; color: "#1e1e2e"; font { pixelSize: 13; bold: true }; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 5; color: parent.pressed ? "#5296e4" : "#89b4fa" }
            }
            Button {
                text: "Cancel"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                contentItem: Text { text: parent.text; color: "#cdd6f4"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 5; color: parent.pressed ? "#313244" : "#45475a" }
            }
            onAccepted: {
                var msg = commitMsgField.text.trim()
                if (!msg) msg = "Update score"
                root.pushRequested(msg)
                commitMsgField.text = ""
                pushDialog.close()
            }
            onRejected: {
                commitMsgField.text = ""
                pushDialog.close()
            }
        }
    }

    // -----------------------------------------------------------------------
    // New branch dialog
    // -----------------------------------------------------------------------
    Dialog {
        id:    newBranchDialog
        title: "Create New Branch"
        modal: true
        anchors.centerIn: parent
        width: 320

        background: Rectangle { color: "#313244"; radius: 8; border.color: "#45475a" }
        header: Rectangle {
            color: "#313244"; radius: 8; height: 44
            Text { anchors.centerIn: parent; text: "➕  New Branch"; color: "#cdd6f4"; font { pixelSize: 15; bold: true } }
        }

        contentItem: ColumnLayout {
            spacing: 12
            width: newBranchDialog.availableWidth

            Text { text: "Branch name:"; color: "#a6adc8"; font.pixelSize: 13 }

            TextField {
                id:    newBranchNameField
                Layout.fillWidth: true
                placeholderText:  "feature/my-variation"
                color:            "#cdd6f4"
                placeholderTextColor: "#585b70"
                font.pixelSize:   13
                background: Rectangle { color: "#1e1e2e"; radius: 4; border.color: "#a6e3a1"; border.width: 1 }
                leftPadding: 8; rightPadding: 8
            }

            Text { text: "Based on: " + root.currentBranch; color: "#585b70"; font.pixelSize: 12 }
        }

        footer: DialogButtonBox {
            background: Rectangle { color: "transparent" }
            Button {
                text: "Create"
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                contentItem: Text { text: parent.text; color: "#1e1e2e"; font { pixelSize: 13; bold: true }; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 5; color: parent.pressed ? "#4dab64" : "#a6e3a1" }
            }
            Button {
                text: "Cancel"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                contentItem: Text { text: parent.text; color: "#cdd6f4"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 5; color: parent.pressed ? "#313244" : "#45475a" }
            }
            onAccepted: {
                var bname = newBranchNameField.text.trim()
                if (bname) {
                    root.branchCreated(bname)
                    newBranchNameField.text = ""
                }
                newBranchDialog.close()
            }
            onRejected: {
                newBranchNameField.text = ""
                newBranchDialog.close()
            }
        }
    }
}
