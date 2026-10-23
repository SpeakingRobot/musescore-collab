// SettingsPanel.qml
// MuseCollab v2 — Settings panel with Register and Join by Code tabs.
// Theme: Catppuccin Mocha dark palette.

import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

Rectangle {
    id: root

    // -----------------------------------------------------------------------
    // Public properties
    // -----------------------------------------------------------------------
    property string initialServerUrl: ""
    property string initialUsername:  ""
    property string initialProject:   ""
    property string initialInviteCode: ""
    property string initialDisplayName: ""

    // Current tab mode: "register" or "join"
    property string mode: "register"

    // -----------------------------------------------------------------------
    // Signals
    // -----------------------------------------------------------------------
    signal settingsSaved(string serverUrl, string username, string token,
                         string projectId, string projectName, string inviteCode,
                         string myBranch, string displayName)
    signal connectionTested(bool success, string message)

    // -----------------------------------------------------------------------
    // Internal state
    // -----------------------------------------------------------------------
    property string _statusText:  ""
    property bool   _statusOk:    true
    property bool   _loading:     false
    property string _savedToken:  ""
    property string _savedInviteCode: ""
    property string _savedProjectId: ""
    property string _savedProjectName: ""
    property string _savedMyBranch: ""

    // -----------------------------------------------------------------------
    // Appearance
    // -----------------------------------------------------------------------
    color:  "#1e1e2e"
    radius: 8

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    Component.onCompleted: {
        regUrlField.text     = root.initialServerUrl
        regUserField.text    = root.initialUsername
        joinUrlField.text    = root.initialServerUrl
        joinUserField.text   = root.initialUsername
        joinCodeField.text   = root.initialInviteCode
        joinNameField.text   = root.initialDisplayName
    }

    // -----------------------------------------------------------------------
    // Helper: styled text field
    // -----------------------------------------------------------------------
    component StyledField: TextField {
        color:                "#cdd6f4"
        placeholderTextColor: "#585b70"
        font.pixelSize:       13
        leftPadding:          10
        rightPadding:         10
        background: Rectangle {
            color:        "#313244"
            radius:       4
            border.color: parent.activeFocus ? "#89b4fa" : "#45475a"
            border.width: 1
        }
    }

    // -----------------------------------------------------------------------
    // Layout
    // -----------------------------------------------------------------------
    ColumnLayout {
        anchors {
            fill:    parent
            margins: 16
        }
        spacing: 14

        // Title
        Text {
            text:  "⚙  Settings"
            font { pixelSize: 20; bold: true }
            color: "#cdd6f4"
        }

        // ---- Tab switcher ----
        Rectangle {
            Layout.fillWidth: true
            height: 38
            color:  "#181825"
            radius: 6

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: [{ label: "📝 Register", val: "register" },
                            { label: "🔑 Join by Code", val: "join" }]

                    Button {
                        property string tabVal: modelData.val
                        text: modelData.label
                        Layout.fillWidth: true
                        height: 38
                        contentItem: Text {
                            text:  parent.text
                            color: root.mode === tabVal ? "#89b4fa" : "#585b70"
                            font { pixelSize: 12; bold: root.mode === tabVal }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: "transparent"
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 2
                                color: root.mode === tabVal ? "#89b4fa" : "transparent"
                            }
                        }
                        onClicked: {
                            root.mode = tabVal
                            root._statusText = ""
                        }
                    }
                }
            }
        }

        // ---- Panel stack (register / join) ----
        StackLayout {
            currentIndex: root.mode === "register" ? 0 : 1
            Layout.fillWidth: true

            // ================================================================
            // REGISTER TAB
            // ================================================================
            ColumnLayout {
                spacing: 12
                Layout.fillWidth: true

                GridLayout {
                    columns:     2
                    columnSpacing: 10
                    rowSpacing:  10
                    Layout.fillWidth: true

                    Text { text: "Server URL"; color: "#a6adc8"; font.pixelSize: 13 }
                    StyledField {
                        id: regUrlField
                        Layout.fillWidth: true
                        placeholderText: "https://your-server.com"
                    }

                    Text { text: "Username"; color: "#a6adc8"; font.pixelSize: 13 }
                    StyledField {
                        id: regUserField
                        Layout.fillWidth: true
                        placeholderText: "your-username"
                    }

                    Text { text: "Password"; color: "#a6adc8"; font.pixelSize: 13 }
                    StyledField {
                        id: regPassField
                        Layout.fillWidth: true
                        placeholderText: "••••••••"
                        echoMode: TextInput.Password
                    }

                    Text { text: "Project Name"; color: "#a6adc8"; font.pixelSize: 13 }
                    StyledField {
                        id: regProjectField
                        Layout.fillWidth: true
                        placeholderText: "my-score-project"
                        text: root.initialProject
                    }
                }

                // Register & Create Project button
                Button {
                    id: regBtn
                    text: root._loading && root.mode === "register" ? "Creating…" : "Register & Create Project"
                    enabled: !root._loading
                    Layout.fillWidth: true
                    contentItem: Text {
                        text:  regBtn.text
                        color: "#1e1e2e"
                        font { pixelSize: 13; bold: true }
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 5
                        color:  regBtn.pressed  ? "#5296e4"
                               : regBtn.hovered ? "#74aaee"
                               :                  "#89b4fa"
                    }
                    onClicked: {
                        var url  = regUrlField.text.trim()
                        var user = regUserField.text.trim()
                        var pass = regPassField.text
                        var proj = regProjectField.text.trim()
                        if (!url || !user || !pass || !proj) {
                            root._statusText = "Please fill in all fields."
                            root._statusOk   = false
                            return
                        }
                        root._loading    = true
                        root._statusText = "Registering account…"
                        root._statusOk   = true
                        _doRegisterAndCreate(url, user, pass, proj)
                    }
                }

                // Invite code result box (shown after project creation)
                Rectangle {
                    Layout.fillWidth: true
                    height: inviteResultCol.implicitHeight + 20
                    color:  "#1a2a1a"
                    radius: 6
                    border.color: "#a6e3a1"
                    border.width: 1
                    visible: root._savedInviteCode.length > 0 && root.mode === "register"

                    ColumnLayout {
                        id: inviteResultCol
                        anchors { fill: parent; margins: 10 }
                        spacing: 6

                        Text {
                            text:  "Share this code with collaborators:"
                            color: "#a6adc8"
                            font.pixelSize: 11
                        }
                        RowLayout {
                            spacing: 8
                            Text {
                                text:  root._savedInviteCode
                                color: "#a6e3a1"
                                font { pixelSize: 18; bold: true; family: "monospace" }
                            }
                            Button {
                                text: "Copy"
                                implicitWidth: 52; implicitHeight: 26
                                contentItem: Text {
                                    text: parent.text; color: "#1e1e2e"; font { pixelSize: 11; bold: true }
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle { radius: 4; color: parent.pressed ? "#4dab64" : "#a6e3a1" }
                                onClicked: {
                                    // Copy to clipboard via TextEdit trick
                                    clipHelper.text = root._savedInviteCode
                                    clipHelper.selectAll()
                                    clipHelper.copy()
                                }
                            }
                        }
                    }
                }
            }

            // ================================================================
            // JOIN TAB
            // ================================================================
            ColumnLayout {
                spacing: 12
                Layout.fillWidth: true

                GridLayout {
                    columns:     2
                    columnSpacing: 10
                    rowSpacing:  10
                    Layout.fillWidth: true

                    Text { text: "Server URL"; color: "#a6adc8"; font.pixelSize: 13 }
                    StyledField {
                        id: joinUrlField
                        Layout.fillWidth: true
                        placeholderText: "https://your-server.com"
                    }

                    Text { text: "Username"; color: "#a6adc8"; font.pixelSize: 13 }
                    StyledField {
                        id: joinUserField
                        Layout.fillWidth: true
                        placeholderText: "your-username"
                    }

                    Text { text: "Password"; color: "#a6adc8"; font.pixelSize: 13 }
                    StyledField {
                        id: joinPassField
                        Layout.fillWidth: true
                        placeholderText: "••••••••"
                        echoMode: TextInput.Password
                    }

                    Text {
                        text: "Your Name"
                        color: "#a6adc8"
                        font.pixelSize: 13
                    }
                    StyledField {
                        id: joinNameField
                        Layout.fillWidth: true
                        placeholderText: "Alice"
                    }
                }

                Text {
                    text: "Your display name (shown to the project owner)"
                    color: "#585b70"
                    font.pixelSize: 11
                    Layout.leftMargin: 2
                }

                // Invite code field — large, centered, monospace
                Rectangle {
                    Layout.fillWidth: true
                    height: 64
                    color:  "#313244"
                    radius: 6
                    border.color: joinCodeField.activeFocus ? "#cba6f7" : "#45475a"
                    border.width: 2

                    TextField {
                        id: joinCodeField
                        anchors.centerIn: parent
                        width: parent.width - 24
                        placeholderText: "BACH-7X2K"
                        placeholderTextColor: "#585b70"
                        color: "#cba6f7"
                        font { pixelSize: 22; bold: true; family: "monospace" }
                        horizontalAlignment: Text.AlignHCenter
                        background: Rectangle { color: "transparent" }
                        // Auto-convert to uppercase
                        onTextChanged: {
                            var up = text.toUpperCase()
                            if (up !== text) {
                                var pos = cursorPosition
                                text = up
                                cursorPosition = pos
                            }
                        }
                    }
                }

                Text {
                    text: "Enter the invite code shared by the project owner"
                    color: "#585b70"
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignHCenter
                }

                // Register & Join button
                Button {
                    id: joinBtn
                    text: root._loading && root.mode === "join" ? "Joining…" : "Register & Join"
                    enabled: !root._loading
                    Layout.fillWidth: true
                    contentItem: Text {
                        text:  joinBtn.text
                        color: "#1e1e2e"
                        font { pixelSize: 13; bold: true }
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 5
                        color:  joinBtn.pressed  ? "#9b6fe8"
                               : joinBtn.hovered ? "#b590f3"
                               :                   "#cba6f7"
                    }
                    onClicked: {
                        var url  = joinUrlField.text.trim()
                        var user = joinUserField.text.trim()
                        var pass = joinPassField.text
                        var code = joinCodeField.text.trim()
                        var dname = joinNameField.text.trim()
                        if (!url || !user || !pass || !code || !dname) {
                            root._statusText = "Please fill in all fields including Your Name."
                            root._statusOk   = false
                            return
                        }
                        root._loading    = true
                        root._statusText = "Registering account…"
                        root._statusOk   = true
                        _doRegisterAndJoin(url, user, pass, code, dname)
                    }
                }

                // Success result after join
                Rectangle {
                    Layout.fillWidth: true
                    height: joinSuccessText.implicitHeight + 20
                    color:  "#1a2a1a"
                    radius: 6
                    border.color: "#a6e3a1"
                    border.width: 1
                    visible: root._savedMyBranch.length > 0 && root.mode === "join"

                    Text {
                        id: joinSuccessText
                        anchors { fill: parent; margins: 10 }
                        text:  "✓ Joined project! Your branch: " + root._savedMyBranch
                        color: "#a6e3a1"
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // ---- Status label ----
        Rectangle {
            Layout.fillWidth: true
            height:  statusLabel.implicitHeight + 12
            color:   root._statusOk ? "#1a2a1a" : "#2a1a1a"
            radius:  4
            visible: root._statusText.length > 0

            Text {
                id:       statusLabel
                anchors { fill: parent; margins: 6 }
                text:     root._statusText
                color:    root._statusOk ? "#a6e3a1" : "#f38ba8"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }

        // Spacer
        Item { Layout.fillHeight: true }

        // Version note
        Text {
            text:  "MuseCollab v2.0.0"
            color: "#585b70"
            font.pixelSize: 11
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // Hidden TextEdit for clipboard copy
    TextEdit {
        id: clipHelper
        visible: false
        text: ""
    }

    // -----------------------------------------------------------------------
    // Register + Create Project flow
    // -----------------------------------------------------------------------
    function _doRegisterAndCreate(url, user, pass, projName) {
        _performXhr("POST", url.replace(/\/$/, "") + "/api/auth/register",
            { "Content-Type": "application/json" },
            JSON.stringify({ username: user, password: pass }),
            function(err, data) {
                if (err) {
                    root._loading    = false
                    root._statusText = "✗ Registration failed: " + err
                    root._statusOk   = false
                    return
                }
                var tok = data && data.token ? data.token : ""
                if (!tok) {
                    root._loading    = false
                    root._statusText = "✗ No token returned from server."
                    root._statusOk   = false
                    return
                }
                root._savedToken = tok
                root._statusText = "Creating project…"

                _performXhr("POST", url.replace(/\/$/, "") + "/api/projects",
                    { "Content-Type": "application/json", "Authorization": "Bearer " + tok },
                    JSON.stringify({ name: projName }),
                    function(err2, data2) {
                        root._loading = false
                        if (err2) {
                            root._statusText = "✗ Project creation failed: " + err2
                            root._statusOk   = false
                            return
                        }
                        var payload = (data2 && data2.data) ? data2.data : data2
                        var pid    = (payload && payload.project ? payload.project.id : (payload && payload.projectId)) || ""
                        var pname  = (payload && payload.project ? payload.project.name : (payload && payload.name)) || projName
                        var icode  = (payload && payload.project ? payload.project.inviteCode : (payload && payload.inviteCode)) || ""
                        root._savedProjectId   = pid
                        root._savedProjectName = pname
                        root._savedInviteCode  = icode
                        root._statusText = "✓ Project created! Invite code: " + icode
                        root._statusOk   = true
                        root.settingsSaved(url, user, tok, pid, pname, icode, "main", user)
                    }
                )
            }
        )
    }

    // -----------------------------------------------------------------------
    // Register + Join Project flow
    // -----------------------------------------------------------------------
    function _doRegisterAndJoin(url, user, pass, code, displayName) {
        _performXhr("POST", url.replace(/\/$/, "") + "/api/auth/register",
            { "Content-Type": "application/json" },
            JSON.stringify({ username: user, password: pass }),
            function(err, data) {
                if (err) {
                    root._loading    = false
                    root._statusText = "✗ Registration failed: " + err
                    root._statusOk   = false
                    return
                }
                var tok = data && data.token ? data.token : ""
                if (!tok) {
                    root._loading    = false
                    root._statusText = "✗ No token returned from server."
                    root._statusOk   = false
                    return
                }
                root._savedToken = tok
                root._statusText = "Joining project…"

                _performXhr("POST", url.replace(/\/$/, "") + "/api/auth/join",
                    { "Content-Type": "application/json", "Authorization": "Bearer " + tok },
                    JSON.stringify({ inviteCode: code, displayName: displayName }),
                    function(err2, data2) {
                        root._loading = false
                        if (err2) {
                            root._statusText = "✗ Join failed: " + err2
                            root._statusOk   = false
                            return
                        }
                        var payload = (data2 && data2.data) ? data2.data : data2
                        var pid    = (payload && payload.project ? payload.project.id : (payload && payload.projectId)) || ""
                        var pname  = (payload && payload.project ? payload.project.name : (payload && payload.projectName)) || ""
                        var branch = (payload && payload.branch ? payload.branch.name : (payload && payload.myBranch)) || (user + "/main")
                        root._savedProjectId   = pid
                        root._savedProjectName = pname
                        root._savedInviteCode  = code
                        root._savedMyBranch    = branch
                        root._statusText = "✓ Joined! Your branch: " + branch
                        root._statusOk   = true
                        root.settingsSaved(url, user, tok, pid, pname, code, branch, displayName)
                    }
                )
            }
        )
    }

    // -----------------------------------------------------------------------
    // Low-level XHR (no dependency on api.js namespace in this file)
    // -----------------------------------------------------------------------
    function _performXhr(method, url, headers, body, cb) {
        var xhr = new XMLHttpRequest()
        xhr.open(method, url, true)
        var hkeys = Object.keys(headers)
        for (var i = 0; i < hkeys.length; i++) {
            xhr.setRequestHeader(hkeys[i], headers[hkeys[i]])
        }
        xhr.timeout = 20000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var parsed = null
            try { parsed = JSON.parse(xhr.responseText) } catch(e) {}
            var st = xhr.status
            if (st >= 200 && st < 300) {
                cb(null, parsed)
            } else {
                var msg = (parsed && (parsed.message || parsed.error)) || ("HTTP " + st)
                cb(msg, null)
            }
        }
        xhr.onerror   = function() { cb("Network error", null) }
        xhr.ontimeout = function() { cb("Timeout", null) }
        if (body) { xhr.send(body) } else { xhr.send() }
    }

    // -----------------------------------------------------------------------
    // Public convenience: pre-populate token if already known
    // -----------------------------------------------------------------------
    function setToken(token) {
        root._savedToken = token
    }
}
