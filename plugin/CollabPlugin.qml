// CollabPlugin.qml
// MuseCollab v2 — Collaborative Version Control & Live Collab for MuseScore 3/4.
// Theme: Catppuccin Mocha.

import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import MuseScore 3.0
import "js/api.js" as Api
import "js/mscxParser.js" as MscxParser
import "js/scoreWriter.js" as ScoreWriter

MuseScore {
    id: pluginRoot

    // -----------------------------------------------------------------------
    // Plugin metadata
    // -----------------------------------------------------------------------
    menuPath:    "Plugins.MuseCollab"
    description: "Git-style collaborative version control and live session for MuseScore"
    version:     "2.0.0"
    pluginType:  "dock"
    dockArea:    "right"
    width:       460
    height:      640

    // -----------------------------------------------------------------------
    // Persistent settings
    // -----------------------------------------------------------------------
    readonly property string defaultCloudUrl: "https://musescore-collab.onrender.com"
    property string serverUrl:     _loadSetting("collab_serverUrl",     defaultCloudUrl)
    property string username:      _loadSetting("collab_username",      "")
    property string token:         _loadSetting("collab_token",         "")
    property string project:       _loadSetting("collab_project",       "")
    property string projectName:   _loadSetting("collab_projectName",   "")
    property string inviteCode:    _loadSetting("collab_inviteCode",    "")
    property string currentBranch: _loadSetting("collab_branch",        "main")
    property string myBranch:      _loadSetting("collab_myBranch",      "main")
    property string displayName:   _loadSetting("collab_displayName",   "")

    // -----------------------------------------------------------------------
    // UI state
    // -----------------------------------------------------------------------
    // 0: Settings, 1: Branches, 2: Measures, 3: Live, 4: Diff
    property int    activeTab:    0
    property bool   loading:      false
    property string errorText:    ""
    property string statusText:   ""

    // Diff / Measure state
    property var    pendingDiffs:     []
    property string diffBaseName:     ""
    property string diffTheirName:    ""
    property var    pendingMeasureDiffs: []

    // Live session state
    property string activeLiveSessionId: ""
    property bool   isLiveHost:          false
    property var    latestLiveSnapshot:  null

    // -----------------------------------------------------------------------
    // onRun: Automatic Reconnection & Resume
    // -----------------------------------------------------------------------
    onRun: {
        var hasSettings = pluginRoot.serverUrl && pluginRoot.token && pluginRoot.project
        if (hasSettings) {
            // Instantly open the collaborative workspace
            pluginRoot.activeTab = 1
            var display = pluginRoot.displayName || pluginRoot.username || "Musician"
            _setStatus("🔄 Reconnecting to " + (pluginRoot.projectName || "Project") + "…")

            // Silently verify session in the background
            Api.getProject(pluginRoot.serverUrl, pluginRoot.token, pluginRoot.project, function (err, data) {
                if (err) {
                    _setError("Session expired or server unavailable. Please check settings.")
                    pluginRoot.activeTab = 0
                } else {
                    if (data && data.project && data.project.name) {
                        pluginRoot.projectName = data.project.name
                        _saveSetting("collab_projectName", data.project.name)
                    }
                    _setStatus("✓ Connected to " + pluginRoot.projectName + " as " + display)
                    autoDismissTimer.restart()
                    if (branchPanel) branchPanel.refreshCollaborators()
                }
            })
        } else {
            pluginRoot.activeTab = 0
        }
    }

    Timer {
        id: autoDismissTimer
        interval: 3500
        repeat: false
        onTriggered: _clearMessages()
    }

    // -----------------------------------------------------------------------
    // Settings persistence via Qt.localStorage
    // -----------------------------------------------------------------------
    function _saveSetting(key, value) {
        try {
            var db = openDatabaseSync("MuseCollab", "2.0", "MuseCollab settings", 2048)
            db.transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)")
                tx.executeSql("INSERT OR REPLACE INTO settings VALUES (?, ?)", [key, value])
            })
        } catch (e) {}
    }

    function _loadSetting(key, defaultValue) {
        try {
            var db = openDatabaseSync("MuseCollab", "2.0", "MuseCollab settings", 2048)
            var result = defaultValue
            db.readTransaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)")
                var rs = tx.executeSql("SELECT value FROM settings WHERE key = ?", [key])
                if (rs.rows.length > 0) {
                    result = rs.rows.item(0).value
                }
            })
            return result
        } catch (e) {
            return defaultValue
        }
    }

    function _saveAllSettings() {
        _saveSetting("collab_serverUrl",   pluginRoot.serverUrl)
        _saveSetting("collab_username",    pluginRoot.username)
        _saveSetting("collab_token",       pluginRoot.token)
        _saveSetting("collab_project",     pluginRoot.project)
        _saveSetting("collab_projectName", pluginRoot.projectName)
        _saveSetting("collab_inviteCode",  pluginRoot.inviteCode)
        _saveSetting("collab_branch",      pluginRoot.currentBranch)
        _saveSetting("collab_myBranch",    pluginRoot.myBranch)
        _saveSetting("collab_displayName", pluginRoot.displayName)
    }

    // -----------------------------------------------------------------------
    // Error / status helpers
    // -----------------------------------------------------------------------
    function _setError(msg) {
        pluginRoot.errorText  = msg
        pluginRoot.statusText = ""
        pluginRoot.loading    = false
    }

    function _setStatus(msg) {
        pluginRoot.statusText = msg
        pluginRoot.errorText  = ""
    }

    function _clearMessages() {
        pluginRoot.errorText  = ""
        pluginRoot.statusText = ""
    }

    // -----------------------------------------------------------------------
    // Core Collaboration Action Handlers
    // -----------------------------------------------------------------------

    // -- Push current score to current branch --
    function handlePush(commitMessage) {
        if (!curScore) {
            _setError("No score is open. Please open a score first.")
            return
        }
        _clearMessages()
        pluginRoot.loading = true
        _setStatus("Reading score notation…")

        var scoreStructure = ScoreWriter.readScoreStructure(curScore)

        _setStatus("Pushing to " + pluginRoot.currentBranch + "…")

        Api.push(pluginRoot.serverUrl,
             pluginRoot.token,
             pluginRoot.project,
             pluginRoot.currentBranch,
             scoreStructure,
             commitMessage || "Update score",
             function (err, data) {
                 pluginRoot.loading = false
                 if (err) {
                     _setError("Push failed: " + err)
                 } else {
                     var cid = (data && data.commitId) ? data.commitId.substring(0, 8) : ""
                     _setStatus("✓ Pushed " + cid + " to " + pluginRoot.currentBranch)
                     autoDismissTimer.restart()
                     branchPanel.refreshCollaborators()
                 }
             }
        )
    }

    // -- Pull branch --
    function handlePull(branch) {
        _clearMessages()
        pluginRoot.loading = true
        _setStatus("Pulling from " + branch + "…")

        Api.pull(pluginRoot.serverUrl,
             pluginRoot.token,
             pluginRoot.project,
             branch,
             function (err, data) {
                 pluginRoot.loading = false
                 if (err) {
                     _setError("Pull failed: " + err)
                     return
                 }
                 if (!data || !data.content) {
                     _setError("Pull completed but no score content was returned.")
                     return
                 }
                 pullResultDialog.content   = data.content
                 pullResultDialog.commitMsg = data.message || ""
                 pullResultDialog.author    = data.author  || ""
                 pullResultDialog.sourceBranch = branch
                 pullResultDialog.open()
                 _setStatus("✓ Pulled latest from " + branch)
                 autoDismissTimer.restart()
             }
        )
    }

    // -- Measure-level cherry-pick diff --
    function handleMeasureDiff(theirBranch) {
        _clearMessages()
        pluginRoot.loading = true
        _setStatus("Comparing measures with " + theirBranch + "…")

        Api.getMeasureDiff(pluginRoot.serverUrl,
                       pluginRoot.token,
                       pluginRoot.project,
                       theirBranch,
                       pluginRoot.currentBranch,
                       function (err, diffs) {
                           pluginRoot.loading = false
                           if (err) {
                               _setError("Measure diff failed: " + err)
                               return
                           }
                           pluginRoot.pendingMeasureDiffs = diffs || []
                           measurePicker.measureDiffs = pluginRoot.pendingMeasureDiffs
                           measurePicker.sourceTitle  = theirBranch
                           measurePicker.baseTitle    = pluginRoot.currentBranch
                           pluginRoot.activeTab       = 2 // Measures tab
                           _setStatus("Found " + (diffs ? diffs.length : 0) + " differing measure(s).")
                       }
        )
    }

    // -- Import selected measures into main score --
    function handleImportMeasures(measureNumbers) {
        if (!measureNumbers || measureNumbers.length === 0) {
            _setError("No measures selected for import.")
            return
        }
        _clearMessages()
        pluginRoot.loading = true
        _setStatus("Importing " + measureNumbers.length + " bar(s) from " + measurePicker.sourceTitle + "…")

        Api.importMeasures(pluginRoot.serverUrl,
                       pluginRoot.token,
                       pluginRoot.project,
                       measurePicker.sourceTitle,
                       measureNumbers,
                       "Import measures " + measureNumbers.join(", ") + " from " + measurePicker.sourceTitle,
                       function (err, data) {
                           pluginRoot.loading = false
                           if (err) {
                               _setError("Import failed: " + err)
                           } else {
                               _setStatus("✓ Successfully imported " + measureNumbers.length + " bar(s) into " + pluginRoot.currentBranch + "!")
                               pluginRoot.activeTab = 1
                               autoDismissTimer.restart()
                               branchPanel.refreshCollaborators()
                           }
                       }
        )
    }

    // -- Note-level diff --
    function handleDiff(theirBranch) {
        _clearMessages()
        pluginRoot.loading = true
        _setStatus("Fetching full diff for " + theirBranch + "…")

        Api.pull(pluginRoot.serverUrl, pluginRoot.token, pluginRoot.project, pluginRoot.currentBranch, function (errA, dataA) {
            if (errA) { _setError("Could not fetch " + pluginRoot.currentBranch + ": " + errA); return }
            Api.pull(pluginRoot.serverUrl, pluginRoot.token, pluginRoot.project, theirBranch, function (errB, dataB) {
                pluginRoot.loading = false
                if (errB) { _setError("Could not fetch " + theirBranch + ": " + errB); return }

                var scoreA, scoreB
                try { scoreA = typeof dataA.content === "string" ? JSON.parse(dataA.content) : dataA.content } catch (e) { scoreA = MscxParser.parseMscx(dataA.content) }
                try { scoreB = typeof dataB.content === "string" ? JSON.parse(dataB.content) : dataB.content } catch (e) { scoreB = MscxParser.parseMscx(dataB.content) }

                var diffs = MscxParser.diffScores(scoreA, scoreB)
                pluginRoot.pendingDiffs  = diffs
                pluginRoot.diffBaseName  = pluginRoot.currentBranch
                pluginRoot.diffTheirName = theirBranch
                pluginRoot.activeTab     = 4 // Diff tab
                _setStatus("Comparing: " + diffs.length + " change(s) found.")
            })
        })
    }

    // -- Apply accepted note changes into curScore --
    function handleApplyNoteChanges(acceptedIndices) {
        if (!curScore) {
            _setError("No score is open.")
            return
        }
        if (!acceptedIndices || acceptedIndices.length === 0) {
            _setError("No changes selected.")
            return
        }
        _clearMessages()
        pluginRoot.loading = true
        _setStatus("Applying " + acceptedIndices.length + " change(s) to score…")

        curScore.startCmd()
        var cursor = curScore.newCursor()
        var diffs  = pluginRoot.pendingDiffs
        var applied = 0

        for (var i = 0; i < acceptedIndices.length; i++) {
            var idx = acceptedIndices[i]
            if (idx >= 0 && idx < diffs.length) {
                var d = diffs[idx]
                if (d.eventB) {
                    var ok = ScoreWriter.applyNoteChange(cursor, d.measureNumber, d.staffIndex - 1, d.voiceIndex, d.eventIndex, d.eventB)
                    if (ok) applied++
                }
            }
        }
        curScore.endCmd()

        pluginRoot.loading   = false
        pluginRoot.activeTab = 1
        _setStatus("✓ Applied " + applied + " change(s) to open score.")
        autoDismissTimer.restart()
    }

    // -----------------------------------------------------------------------
    // Live Collab Handlers
    // -----------------------------------------------------------------------

    function handleStartLive() {
        _clearMessages()
        pluginRoot.loading = true
        _setStatus("Starting live session…")

        Api.startLiveSession(pluginRoot.serverUrl, pluginRoot.token, pluginRoot.project, function (err, data) {
            pluginRoot.loading = false
            if (err) {
                _setError("Failed to start live session: " + err)
                return
            }
            pluginRoot.activeLiveSessionId = data.sessionId
            pluginRoot.isLiveHost          = true
            livePanel.isHost               = true
            livePanel.sessionId            = data.sessionId
            livePanel.hostUsername         = pluginRoot.displayName || pluginRoot.username
            branchPanel.isLive             = true

            // Send first snapshot
            handleBroadcastScore()
            livePollTimer.restart()
            pluginRoot.activeTab = 3 // Live tab
            _setStatus("🔴 You are now live!")
        })
    }

    function handleJoinLive(sessionId) {
        _clearMessages()
        pluginRoot.activeLiveSessionId = sessionId
        pluginRoot.isLiveHost          = false
        livePanel.isHost               = false
        livePanel.sessionId            = sessionId
        livePollTimer.restart()
        pluginRoot.activeTab           = 3
        _setStatus("🔴 Joined live session.")
    }

    function handleStopLive() {
        livePollTimer.stop()
        if (pluginRoot.isLiveHost && pluginRoot.activeLiveSessionId) {
            Api.endLiveSession(pluginRoot.serverUrl, pluginRoot.token, pluginRoot.activeLiveSessionId, function () {})
        }
        pluginRoot.activeLiveSessionId = ""
        pluginRoot.isLiveHost          = false
        branchPanel.isLive             = false
        pluginRoot.activeTab           = 1
        _setStatus("Live session ended.")
        autoDismissTimer.restart()
    }

    function handleBroadcastScore() {
        if (!curScore) return
        var structure = ScoreWriter.readScoreStructure(curScore)
        Api.sendLiveSnapshot(pluginRoot.serverUrl, pluginRoot.token, pluginRoot.activeLiveSessionId, structure, function (err, res) {
            if (!err) {
                livePanel.lastSnapshotTime = new Date().toLocaleTimeString()
            }
        })
    }

    // Live session polling timer (every 2.5 seconds)
    Timer {
        id: livePollTimer
        interval: 2500
        repeat: true
        running: false
        onTriggered: {
            if (!pluginRoot.activeLiveSessionId) return

            Api.getLiveSnapshot(pluginRoot.serverUrl, pluginRoot.token, pluginRoot.activeLiveSessionId, function (err, res) {
                if (err) return
                if (res && res.data) {
                    var d = res.data
                    livePanel.hostUsername = d.hostUsername || "Host"
                    livePanel.watcherCount = d.watcherCount || 0
                    if (d.lastSnapshot) {
                        pluginRoot.latestLiveSnapshot = d.lastSnapshot
                        livePanel.lastSnapshot = d.lastSnapshot
                        if (d.lastSnapshotTime) livePanel.lastSnapshotTime = d.lastSnapshotTime
                    }
                    if (pluginRoot.isLiveHost && d.suggestions && d.suggestions.length > 0) {
                        livePanel.clearSuggestions()
                        for (var i = 0; i < d.suggestions.length; i++) {
                            livePanel.addSuggestion(d.suggestions[i])
                        }
                    }
                }
            })
        }
    }

    // -----------------------------------------------------------------------
    // UI Layout
    // -----------------------------------------------------------------------
    Rectangle {
        id:           pluginPane
        color:        "#1e1e2e"
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---- Top Navigation Tab Bar ----
            Rectangle {
                Layout.fillWidth: true
                height: 44
                color:  "#181825"

                RowLayout {
                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                    spacing: 0

                    Repeater {
                        model: [
                            { name: "⚙ Setup",    idx: 0 },
                            { name: "🌿 Collab",   idx: 1 },
                            { name: "📐 Bars",     idx: 2 },
                            { name: "🔴 Live",     idx: 3 },
                            { name: "🔀 Diff",     idx: 4 }
                        ]

                        Button {
                            property int tabIdx: modelData.idx
                            Layout.fillWidth: true
                            height: 44

                            contentItem: Text {
                                text:  modelData.name
                                color: pluginRoot.activeTab === tabIdx ? "#89b4fa" : "#585b70"
                                font { pixelSize: 11; bold: pluginRoot.activeTab === tabIdx }
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment:   Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: "transparent"
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width; height: 2
                                    color: pluginRoot.activeTab === tabIdx ? "#89b4fa" : "transparent"
                                }
                            }
                            onClicked: {
                                pluginRoot.activeTab = tabIdx
                                _clearMessages()
                            }
                        }
                    }
                }
            }

            // ---- Loading indicator ----
            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running:  pluginRoot.loading
                visible:  pluginRoot.loading
                height:   28
                width:    28
            }

            // ---- Status / Error banners ----
            Rectangle {
                Layout.fillWidth: true
                height:  bannerText.implicitHeight + 10
                color:   pluginRoot.errorText ? "#2e1a22" : "#1a2e22"
                visible: pluginRoot.errorText.length > 0 || pluginRoot.statusText.length > 0

                Text {
                    id: bannerText
                    anchors { fill: parent; margins: 6 }
                    text: pluginRoot.errorText || pluginRoot.statusText
                    color: pluginRoot.errorText ? "#f38ba8" : "#a6e3a1"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                MouseArea { anchors.fill: parent; onClicked: _clearMessages() }
            }

            // ---- Panel Views (StackLayout) ----
            StackLayout {
                id: mainStack
                currentIndex: pluginRoot.activeTab
                Layout.fillWidth:  true
                Layout.fillHeight: true

                // Tab 0: Settings & Join Panel
                SettingsPanel {
                    id: settingsPanel
                    initialServerUrl:   pluginRoot.serverUrl
                    initialUsername:    pluginRoot.username
                    initialProject:     pluginRoot.projectName
                    initialInviteCode:  pluginRoot.inviteCode
                    initialDisplayName: pluginRoot.displayName

                    onSettingsSaved: function (sUrl, sUser, sToken, sProjId, sProjName, sCode, sBranch, sName) {
                        pluginRoot.serverUrl     = sUrl
                        pluginRoot.username      = sUser
                        if (sToken) pluginRoot.token = sToken
                        if (sProjId) pluginRoot.project = sProjId
                        if (sProjName) pluginRoot.projectName = sProjName
                        if (sCode) pluginRoot.inviteCode = sCode
                        if (sBranch) {
                            pluginRoot.currentBranch = sBranch
                            pluginRoot.myBranch      = sBranch
                        }
                        if (sName) pluginRoot.displayName = sName

                        _saveAllSettings()
                        _setStatus("✓ Connected to " + pluginRoot.projectName)
                        pluginRoot.activeTab = 1
                        autoDismissTimer.restart()
                    }

                    onConnectionTested: function (success, message) {
                        if (success) _setStatus("Connection OK: " + message)
                        else _setError("Connection error: " + message)
                    }
                }

                // Tab 1: Branches & Collaborators
                BranchPanel {
                    id: branchPanel
                    serverUrl:     pluginRoot.serverUrl
                    token:         pluginRoot.token
                    project:       pluginRoot.project
                    currentBranch: pluginRoot.currentBranch
                    myBranch:      pluginRoot.myBranch
                    displayName:   pluginRoot.displayName
                    inviteCode:    pluginRoot.inviteCode

                    onCurrentBranchChanged: {
                        pluginRoot.currentBranch = branchPanel.currentBranch
                        _saveSetting("collab_branch", branchPanel.currentBranch)
                    }

                    onPushRequested:        function (msg) { handlePush(msg) }
                    onPullRequested:        function (b)   { handlePull(b) }
                    onMeasureDiffRequested: function (b)   { handleMeasureDiff(b) }
                    onDiffRequested:        function (b)   { handleDiff(b) }
                    onViewRequested:        function (b)   { handlePull(b) }
                    onGoLiveRequested:      function ()    { handleStartLive() }
                    onStopLiveRequested:    function ()    { handleStopLive() }
                    onWatchLiveRequested:   function (sId) { handleJoinLive(sId) }
                }

                // Tab 2: Measure-level Cherry-picker
                MeasurePicker {
                    id: measurePicker
                    measureDiffs: pluginRoot.pendingMeasureDiffs
                    baseTitle:    pluginRoot.currentBranch

                    onImportRequested: function (measureNums) {
                        handleImportMeasures(measureNums)
                    }
                    onCancelled: {
                        pluginRoot.activeTab = 1
                        _clearMessages()
                    }
                }

                // Tab 3: Real-time Live Session
                LivePanel {
                    id: livePanel
                    isHost:           pluginRoot.isLiveHost
                    sessionId:        pluginRoot.activeLiveSessionId

                    onBroadcastScore: handleBroadcastScore()
                    onStopSession:    handleStopLive()
                    onLeaveSession:   handleStopLive()

                    onViewDiffRequested: function (snapshot) {
                        if (curScore && snapshot) {
                            var localScore = ScoreWriter.readScoreStructure(curScore)
                            var diffs = MscxParser.diffScores(localScore, snapshot)
                            pluginRoot.pendingDiffs  = diffs
                            pluginRoot.diffBaseName  = "My Score"
                            pluginRoot.diffTheirName = "Live Session"
                            pluginRoot.activeTab     = 4 // Diff tab
                        }
                    }

                    onSendSuggestion: function (mNum, fNote, tNote, desc) {
                        Api.sendLiveSuggestion(pluginRoot.serverUrl, pluginRoot.token, pluginRoot.activeLiveSessionId, mNum, fNote, tNote, desc, function (err, res) {
                            if (!err) _setStatus("✓ Suggestion sent to host.")
                        })
                    }

                    onSuggestionAccepted: function (sugg) {
                        if (curScore) {
                            curScore.startCmd()
                            var cursor = curScore.newCursor()
                            var targetPitch = ScoreWriter.nameToPitch(sugg.toNote)
                            if (targetPitch > 0) {
                                ScoreWriter.applyNoteChange(cursor, sugg.measureNumber, 0, 0, 0, { type: "note", pitch: targetPitch, tpc: 14, durationType: "quarter" })
                            }
                            curScore.endCmd()
                            handleBroadcastScore()
                            _setStatus("✓ Applied suggestion in Bar " + sugg.measureNumber)
                        }
                    }
                }

                // Tab 4: Note-level Diff Viewer
                DiffViewer {
                    id: diffViewer
                    diffData:        pluginRoot.pendingDiffs
                    baseScoreTitle:  pluginRoot.diffBaseName
                    theirScoreTitle: pluginRoot.diffTheirName

                    onChangesApplied: function (acceptedIndices) {
                        handleApplyNoteChanges(acceptedIndices)
                    }
                    onClosed: {
                        pluginRoot.activeTab = 1
                        _clearMessages()
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Pull-Result Dialog
    // -----------------------------------------------------------------------
    Dialog {
        id: pullResultDialog
        modal: true
        anchors.centerIn: pluginPane
        width: 310

        property var    content:      null
        property string commitMsg:    ""
        property string author:       ""
        property string sourceBranch: ""

        background: Rectangle { color: "#313244"; radius: 8; border.color: "#45475a" }
        header: Rectangle {
            color: "#313244"; radius: 8; height: 42
            Text { anchors.centerIn: parent; text: "📥  Pulled " + pullResultDialog.sourceBranch; color: "#cdd6f4"; font { pixelSize: 14; bold: true } }
        }

        contentItem: ColumnLayout {
            spacing: 8
            width: pullResultDialog.availableWidth

            Text { text: "Latest commit:"; color: "#a6adc8"; font.pixelSize: 11 }
            Text {
                text: pullResultDialog.commitMsg || "(no message)"
                color: "#cdd6f4"; font.pixelSize: 12
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Text { text: "Author: " + (pullResultDialog.author || "Collaborator"); color: "#585b70"; font.pixelSize: 11 }
            Rectangle { height: 1; color: "#45475a"; Layout.fillWidth: true }
            Text {
                text: "Choose how to inspect these changes:"
                color: "#a6adc8"; font.pixelSize: 11
            }
        }

        footer: DialogButtonBox {
            background: Rectangle { color: "transparent" }
            Button {
                text: "Pick Bars"
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                contentItem: Text { text: parent.text; color: "#1e1e2e"; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 5; color: "#89b4fa"; implicitWidth: 80; implicitHeight: 28 }
            }
            Button {
                text: "Done"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                contentItem: Text { text: parent.text; color: "#cdd6f4"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 5; color: "#45475a"; implicitWidth: 60; implicitHeight: 28 }
            }
            onAccepted: {
                handleMeasureDiff(pullResultDialog.sourceBranch)
                pullResultDialog.close()
            }
            onRejected: pullResultDialog.close()
        }
    }
}
