// SettingsPanel.qml
// MuseCollab v2 — Frictionless Project Creation and Joining (No Passwords or Unique Usernames required).
// Theme: Catppuccin Mocha dark palette.

import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

Rectangle {
    id: root

    // -----------------------------------------------------------------------
    // Public properties
    // -----------------------------------------------------------------------
    property string initialServerUrl:   "https://musescore-collab.onrender.com"
    property string initialUsername:    ""
    property string initialProject:     ""
    property string initialInviteCode:  ""
    property string initialDisplayName: ""

    // Current tab mode: "create" or "join"
    property string mode: "create"

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
    property string _statusText:      ""
    property bool   _statusOk:        true
    property bool   _loading:         false
    property string _savedToken:      ""
    property string _savedInviteCode: ""
    property string _savedProjectId:  ""
    property string _savedProjectName:""
    property string _savedMyBranch:   ""

    // -----------------------------------------------------------------------
    // Appearance
    // -----------------------------------------------------------------------
    color:  "#1e1e2e"
    radius: 8

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    Component.onCompleted: {
        var defaultUrl = root.initialServerUrl || "https://musescore-collab.onrender.com"
        serverUrlField.text     = defaultUrl
        createNameField.text    = root.initialDisplayName || root.initialUsername
        createProjectField.text = root.initialProject
        joinNameField.text      = root.initialDisplayName || root.initialUsername
        joinCodeField.text      = root.initialInviteCode

        if (root.initialInviteCode && root.initialInviteCode.length > 0) {
            root.mode = "join"
        }
    }

    // -----------------------------------------------------------------------
    // Layout
    // -----------------------------------------------------------------------
    ColumnLayout {
        anchors {
            fill:    parent
            margins: 18
        }
        spacing: 16

        // Title
        RowLayout {
            spacing: 8
            Text {
                text:  "🎵  MuseCollab"
                font.pixelSize: 22
                font.bold: true
                color: "#cdd6f4"
            }
            Text {
                text:  "v2.0"
                font.pixelSize: 11
                color: "#89b4fa"
                Layout.alignment: Qt.AlignBaseline
            }
        }

        // Subtitle instructions
        Text {
            text:  root.mode === "create"
                   ? "Start a new collaboration project and share the invite code with your friends."
                   : "Enter your friend's invite code and your name to join their music project."
            font.pixelSize: 12
            color: "#a6adc8"
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // ---- Tab switcher ----
        Rectangle {
            Layout.fillWidth: true
            height: 40
            color:  "#181825"
            radius: 6

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: [{ label: "🎼  Create Project", val: "create" },
                            { label: "🔑  Join by Code", val: "join" }]

                    Button {
                        property string tabVal: modelData.val
                        text: modelData.label
                        Layout.fillWidth: true
                        height: 40
                        contentItem: Text {
                            text:  parent.text
                            color: root.mode === tabVal ? "#89b4fa" : "#6c7086"
                            font.pixelSize: 13
                            font.bold: root.mode === tabVal
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

        // ---- Mode Stack (Create / Join) ----
        StackLayout {
            currentIndex: root.mode === "create" ? 0 : 1
            Layout.fillWidth: true

            // ================================================================
            // TAB 1: CREATE PROJECT
            // ================================================================
            ColumnLayout {
                spacing: 14
                Layout.fillWidth: true

                Text { text: "Your Name"; color: "#a6adc8"; font.pixelSize: 13; font.bold: true }
                StyledField {
                    id: createNameField
                    Layout.fillWidth: true
                    placeholderText: "e.g. Sam, Rahul, Alice"
                }

                Text { text: "Project Name"; color: "#a6adc8"; font.pixelSize: 13; font.bold: true }
                StyledField {
                    id: createProjectField
                    Layout.fillWidth: true
                    placeholderText: "e.g. String Quartet No. 1"
                }

                Item { height: 4 }

                Button {
                    id: createBtn
                    text: root._loading && root.mode === "create" ? "Creating Project…" : "🚀  Create Project & Get Invite Code"
                    enabled: !root._loading
                    Layout.fillWidth: true
                    height: 42
                    contentItem: Text {
                        text:  createBtn.text
                        color: "#1e1e2e"
                        font.pixelSize: 14
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 6
                        color: createBtn.pressed ? "#5296e4" : createBtn.hovered ? "#74aaee" : "#89b4fa"
                    }
                    onClicked: {
                        var url  = serverUrlField.text.trim() || root.initialServerUrl
                        var name = createNameField.text.trim()
                        var proj = createProjectField.text.trim()
                        if (!name) { root._statusText = "Please enter your name."; root._statusOk = false; return; }
                        if (!proj) { root._statusText = "Please enter a project name."; root._statusOk = false; return; }
                        _doCreateProject(url, name, proj)
                    }
                }
            }

            // ================================================================
            // TAB 2: JOIN PROJECT
            // ================================================================
            ColumnLayout {
                spacing: 14
                Layout.fillWidth: true

                Text { text: "Your Name"; color: "#a6adc8"; font.pixelSize: 13; font.bold: true }
                StyledField {
                    id: joinNameField
                    Layout.fillWidth: true
                    placeholderText: "e.g. Rahul, David, Maya"
                }

                Text { text: "Project Invite Code (from the host)"; color: "#a6adc8"; font.pixelSize: 13; font.bold: true }
                StyledField {
                    id: joinCodeField
                    Layout.fillWidth: true
                    placeholderText: "e.g. BACH7X2K"
                    font.capitalization: Font.AllUppercase
                    font.pixelSize: 16
                    font.bold: true
                }

                Item { height: 4 }

                Button {
                    id: joinBtn
                    text: root._loading && root.mode === "join" ? "Joining Project…" : "🎵  Join Project"
                    enabled: !root._loading
                    Layout.fillWidth: true
                    height: 42
                    contentItem: Text {
                        text:  joinBtn.text
                        color: "#1e1e2e"
                        font.pixelSize: 14
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 6
                        color: joinBtn.pressed ? "#4dab64" : joinBtn.hovered ? "#6ec984" : "#a6e3a1"
                    }
                    onClicked: {
                        var url  = serverUrlField.text.trim() || root.initialServerUrl
                        var name = joinNameField.text.trim()
                        var code = joinCodeField.text.trim().toUpperCase()
                        if (!name) { root._statusText = "Please enter your name."; root._statusOk = false; return; }
                        if (!code) { root._statusText = "Please enter the invite code."; root._statusOk = false; return; }
                        _doJoinProject(url, name, code)
                    }
                }
            }
        }

        // Status banner
        Rectangle {
            Layout.fillWidth: true
            height: statusLabel.implicitHeight + 14
            color:  root._statusOk ? "#1a2e22" : "#2e1a22"
            radius: 6
            visible: root._statusText.length > 0

            Text {
                id: statusLabel
                anchors.centerIn: parent
                width: parent.width - 16
                text: root._statusText
                color: root._statusOk ? "#a6e3a1" : "#f38ba8"
                font.pixelSize: 12
                font.bold: true
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Item { Layout.fillHeight: true }

        // Subtle Server URL row at bottom
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Cloud Server:"
                color: "#585b70"
                font.pixelSize: 11
            }

            StyledField {
                id: serverUrlField
                Layout.fillWidth: true
                font.pixelSize: 11
                text: root.initialServerUrl || "https://musescore-collab.onrender.com"
            }
        }
    }

    // -----------------------------------------------------------------------
    // Handlers
    // -----------------------------------------------------------------------

    function _doCreateProject(url, name, proj) {
        root._loading = true
        root._statusText = "Creating project…"
        root._statusOk = true

        _performXhr("POST", url.replace(/\/$/, "") + "/api/auth/create-project",
            { "Content-Type": "application/json" },
            JSON.stringify({ displayName: name, projectName: proj }),
            function(err, data) {
                root._loading = false
                if (err) {
                    root._statusText = "✗ Failed: " + err
                    root._statusOk = false
                    return
                }

                var res = (data && data.data) ? data.data : data
                var tok = (res && res.token) || (data && data.token) || ""
                var pid = (res && res.project) ? res.project.id : ""
                var pname = (res && res.project) ? res.project.name : proj
                var icode = (res && res.project) ? res.project.inviteCode : ""
                var branch = (res && res.branch) || "main"

                root._savedToken = tok
                root._savedProjectId = pid
                root._savedProjectName = pname
                root._savedInviteCode = icode
                root._savedMyBranch = branch

                root._statusText = "✓ Project created! Share code: " + icode
                root._statusOk = true

                root.settingsSaved(url, name, tok, pid, pname, icode, branch, name)
            }
        )
    }

    function _doJoinProject(url, name, code) {
        root._loading = true
        root._statusText = "Joining project…"
        root._statusOk = true

        _performXhr("POST", url.replace(/\/$/, "") + "/api/auth/join-project",
            { "Content-Type": "application/json" },
            JSON.stringify({ displayName: name, inviteCode: code }),
            function(err, data) {
                root._loading = false
                if (err) {
                    root._statusText = "✗ Failed: " + err
                    root._statusOk = false
                    return
                }

                var res = (data && data.data) ? data.data : data
                var tok = (res && res.token) || (data && data.token) || ""
                var pid = (res && res.project) ? res.project.id : ""
                var pname = (res && res.project) ? res.project.name : "Project"
                var icode = (res && res.project) ? res.project.inviteCode : code
                var branch = (res && res.branch) || (name + "/main")

                root._savedToken = tok
                root._savedProjectId = pid
                root._savedProjectName = pname
                root._savedInviteCode = icode
                root._savedMyBranch = branch

                root._statusText = "✓ Joined " + pname + "! Branch: " + branch
                root._statusOk = true

                root.settingsSaved(url, name, tok, pid, pname, icode, branch, name)
            }
        )
    }

    // -----------------------------------------------------------------------
    // Low-level XHR
    // -----------------------------------------------------------------------
    function _performXhr(method, url, headers, body, cb) {
        var xhr = new XMLHttpRequest()
        xhr.open(method, url, true)
        var hkeys = Object.keys(headers)
        for (var i = 0; i < hkeys.length; i++) {
            xhr.setRequestHeader(hkeys[i], headers[hkeys[i]])
        }
        xhr.timeout = 25000
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
        xhr.onerror   = function() { cb("Could not connect to server. Check connection.", null) }
        xhr.ontimeout = function() { cb("Server response timed out. Try again.", null) }
        if (body) { xhr.send(body) } else { xhr.send() }
    }
}
