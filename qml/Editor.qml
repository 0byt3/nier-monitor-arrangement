import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root
    title: strings.t("Monitor arrangement")
    implicitWidth: 1100
    implicitHeight: 740
    minimumSize: Qt.size(880, 620)
    color: theme.background
    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.background: theme.background
    Material.foreground: theme.foreground

    property string helper: Quickshell.env("NIER_MONITOR_ARRANGEMENT_BACKEND") || "/usr/share/nier/bin/nier-monitor-arrangement-backend"
    property var snapshot: null
    property int selected: -1
    property bool busy: false
    property bool dirty: false
    property bool ready: false
    property bool snapEdges: true
    property string messageKey: "Loading displays…"
    readonly property string message: strings.t(messageKey)
    property bool error: false
    property string action: "snapshot"
    property string request: ""
    property bool forceReload: false
    property real viewScale: 0.15
    property real offsetX: 70
    property real offsetY: 100
    property int contentRevision: 0
    property var demoSnapshot: null
    property string pendingDiscard: ""
    readonly property var selectedMonitor: {
        contentRevision
        return selected >= 0 && selected < monitors.count ? monitors.get(selected) : null
    }
    readonly property bool overlapping: {
        contentRevision
        for (let i = 0; i < monitors.count; i++) {
            const a = monitors.get(i)
            for (let j = 0; j < i; j++) {
                const b = monitors.get(j)
                if (a.posX < b.posX + b.logicalWidth && a.posX + a.logicalWidth > b.posX && a.posY < b.posY + b.logicalHeight && a.posY + a.logicalHeight > b.posY) return true
            }
        }
        return false
    }

    Theme { id: theme }
    Strings { id: strings }
    ListModel { id: monitors }

    function notify(text, failed) { messageKey = text; error = !!failed }
    function run(command, payload) {
        if (busy || demoSnapshot) return
        action = command
        request = payload ? JSON.stringify(payload) : ""
        busy = true
        runner.stdinEnabled = command === "save"
        runner.command = [helper, command]
        runner.running = true
    }
    function acceptSnapshot(data, force) {
        const changed = snapshot && snapshot.fingerprint !== data.fingerprint
        if (dirty && !changed && !force) return
        const oldName = selectedMonitor ? selectedMonitor.name : ""
        snapshot = data
        monitors.clear()
        for (const m of data.monitors) {
            monitors.append({name: m.name, description: m.description || m.model || m.name,
                identity: m.identity, posX: m.x, posY: m.y, logicalWidth: m.logicalWidth,
                logicalHeight: m.logicalHeight, pixelWidth: m.width, pixelHeight: m.height,
                displayScale: m.scale})
        }
        selected = monitors.count > 0 ? 0 : -1
        for (let i = 0; i < monitors.count; i++) if (monitors.get(i).name === oldName) selected = i
        dirty = false
        contentRevision++
        if (!ready || changed || force) Qt.callLater(fit)
        ready = true
        if (changed) notify("Monitors changed; the editor was refreshed.", true)
    }
    function response(text) {
        let data
        try { data = JSON.parse(text) } catch (e) { notify("The monitor helper returned an invalid response.", true); return }
        if (action === "snapshot") {
            if (data.ok && data.snapshot) {
                const first = !ready
                acceptSnapshot(data.snapshot, forceReload)
                if (first) notify("Ready", false)
            } else notify(data.error || "Could not read displays.", true)
            forceReload = false
        } else {
            if (data.saved) dirty = false
            if (data.snapshot) acceptSnapshot(data.snapshot, true)
            if (data.ok && data.pending) notify("Saved. Layout will apply when displays wake.", false)
            else if (data.ok) notify("Saved and applied.", false)
            else notify(data.error || "Could not save the arrangement.", true)
        }
    }
    function positions() {
        const result = []
        for (let i = 0; i < monitors.count; i++) {
            const m = monitors.get(i)
            result.push({name: m.name, x: m.posX, y: m.posY})
        }
        return result
    }
    function save() {
        if (!snapshot || busy || overlapping) return
        run("save", {fingerprint: snapshot.fingerprint, revision: snapshot.revision, monitors: positions()})
    }
    function setPosition(index, x, y) {
        if (busy || index < 0 || index >= monitors.count || !isFinite(x) || !isFinite(y)) return
        x = Math.max(-65536, Math.min(65536, Math.round(x)))
        y = Math.max(-65536, Math.min(65536, Math.round(y)))
        const m = monitors.get(index)
        if (x === m.posX && y === m.posY) return
        monitors.setProperty(index, "posX", x)
        monitors.setProperty(index, "posY", y)
        dirty = true
        contentRevision++
    }
    function snap(index, x, y) {
        if (!snapEdges) return {x: x, y: y}
        const m = monitors.get(index)
        const tolerance = 10 / viewScale
        let bestX = tolerance, bestY = tolerance, resultX = x, resultY = y
        for (let i = 0; i < monitors.count; i++) {
            if (i === index) continue
            const other = monitors.get(i)
            const xs = [other.posX, other.posX + other.logicalWidth, other.posX - m.logicalWidth, other.posX + other.logicalWidth - m.logicalWidth]
            const ys = [other.posY, other.posY + other.logicalHeight, other.posY - m.logicalHeight, other.posY + other.logicalHeight - m.logicalHeight]
            for (const candidate of xs) if (Math.abs(candidate-x) < bestX) { bestX = Math.abs(candidate-x); resultX = candidate }
            for (const candidate of ys) if (Math.abs(candidate-y) < bestY) { bestY = Math.abs(candidate-y); resultY = candidate }
        }
        return {x: resultX, y: resultY}
    }
    function fit() {
        if (!monitors.count || canvas.width < 1) return
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
        for (let i = 0; i < monitors.count; i++) {
            const m = monitors.get(i)
            minX = Math.min(minX, m.posX); minY = Math.min(minY, m.posY)
            maxX = Math.max(maxX, m.posX + m.logicalWidth); maxY = Math.max(maxY, m.posY + m.logicalHeight)
        }
        viewScale = Math.min(0.5, (canvas.width-100)/Math.max(1,maxX-minX), (canvas.height-100)/Math.max(1,maxY-minY))
        offsetX = (canvas.width-(maxX-minX)*viewScale)/2-minX*viewScale
        offsetY = (canvas.height-(maxY-minY)*viewScale)/2-minY*viewScale
    }
    function automaticRow() {
        let x = 0, laptop = -1
        for (let i = 0; i < monitors.count; i++) {
            const m = monitors.get(i)
            if (m.name === "eDP-1") { laptop = i; continue }
            setPosition(i, x, 0); x += m.logicalWidth
        }
        if (laptop >= 0) setPosition(laptop, x, 0)
        fit()
    }
    function savedLayout() {
        if (!snapshot || !snapshot.arrangement) { notify("No saved arrangement for these displays.", false); return }
        for (let i = 0; i < monitors.count; i++) {
            const p = snapshot.arrangement[monitors.get(i).identity]
            if (p) setPosition(i, p.x, p.y)
        }
        fit()
        notify("Saved arrangement loaded for editing.", false)
    }
    function align(alignment) {
        if (selected < 0) return
        const reference = monitors.get(selected)
        for (let i = 0; i < monitors.count; i++) {
            if (i === selected) continue
            const m = monitors.get(i)
            let y = reference.posY
            if (alignment === "center") y += (reference.logicalHeight-m.logicalHeight)/2
            if (alignment === "bottom") y += reference.logicalHeight-m.logicalHeight
            setPosition(i,m.posX,y)
        }
        fit()
    }
    function reload() {
        if (dirty) { pendingDiscard = "reload"; discardDialog.open(); return }
        forceReload = true
        run("snapshot")
        notify("Live layout reloaded.", false)
    }
    function requestClose() {
        if (dirty) { pendingDiscard = "quit"; discardDialog.open() }
        else Qt.quit()
    }

    Component.onCompleted: {
        if (demoSnapshot) { acceptSnapshot(demoSnapshot,true); notify("Ready",false) }
        else run("snapshot")
    }
    onClosed: {
        if (dirty) { visible = true; pendingDiscard = "quit"; discardDialog.open() }
        else Qt.quit()
    }

    Process {
        id: runner
        onStarted: {
            if (root.action === "save") {
                write(root.request + "\n")
                stdinEnabled = false
            }
        }
        stdout: StdioCollector { onStreamFinished: root.response(text) }
        stderr: StdioCollector { }
        onExited: function(exitCode, exitStatus) { root.busy = false }
    }
    Timer { interval: 3000; repeat: true; running: !root.demoSnapshot; onTriggered: if (!root.busy) root.run("snapshot") }

    Shortcut { sequence: "Ctrl+S"; onActivated: root.save() }
    Shortcut { sequence: "Ctrl+R"; onActivated: root.reload() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: root.requestClose() }
    Shortcut { sequence: "F"; onActivated: root.fit() }

    IpcHandler {
        target: "arrangement"
        function status(): string { return JSON.stringify({ready: root.ready, busy: root.busy, dirty: root.dirty, overlapping: root.overlapping, message: root.message, monitors: root.positions()}) }
        function move(name: string, x: int, y: int): void {
            for (let i=0;i<monitors.count;i++) if (monitors.get(i).name===name) {root.selected=i;root.setPosition(i,x,y);return}
        }
        function save(): void { root.save() }
        function capture(path: string): void { appContent.grabToImage(function(result) { result.saveToFile(path) }) }
    }

    Rectangle {
        id: appContent
        anchors.fill: parent
        color: theme.background
        Material.theme: Material.Dark
        Material.accent: theme.accent
        Material.background: theme.background
        Material.foreground: theme.foreground
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 26
        spacing: 18
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 5
                Label { text: strings.t("Arrange your displays"); textFormat: Text.PlainText; font.pixelSize: 26; font.weight: Font.DemiBold; color: theme.foreground }
                Label { text: strings.t("Drag displays to match your desk. Use X and Y for precise placement."); textFormat: Text.PlainText; font.pixelSize: 13; color: theme.muted }
            }
            Item { Layout.fillWidth: true }
            Button { text: strings.t("Reload"); enabled: !root.busy; onClicked: root.reload() }
            Button { text: strings.t("Save & apply"); highlighted: true; enabled: root.ready && !root.busy && !root.overlapping && !root.demoSnapshot; onClicked: root.save() }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 18
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Rectangle {
                    id: canvas
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: theme.panel
                    border.color: Qt.rgba(theme.foreground.r,theme.foreground.g,theme.foreground.b,0.12)
                    clip: true
                    onWidthChanged: if (root.ready) Qt.callLater(root.fit)
                    onHeightChanged: if (root.ready) Qt.callLater(root.fit)
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            const ctx=getContext("2d"); ctx.reset(); ctx.strokeStyle=Qt.rgba(theme.foreground.r,theme.foreground.g,theme.foreground.b,0.045); ctx.lineWidth=1
                            for(let x=0;x<width;x+=24){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x,height);ctx.stroke()}
                            for(let y=0;y<height;y+=24){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(width,y);ctx.stroke()}
                        }
                    }
                    Repeater {
                        model: monitors
                        Rectangle {
                            id: screenBox
                            required property int index
                            required property string name
                            required property int posX
                            required property int posY
                            required property int logicalWidth
                            required property int logicalHeight
                            x: root.offsetX+posX*root.viewScale
                            y: root.offsetY+posY*root.viewScale
                            width: logicalWidth*root.viewScale
                            height: logicalHeight*root.viewScale
                            color: root.selected === index ? Qt.rgba(theme.accent.r,theme.accent.g,theme.accent.b,0.19) : Qt.lighter(theme.panel,1.35)
                            border.width: root.selected === index ? 2 : 1
                            border.color: root.selected === index ? theme.accent : theme.muted
                            z: dragger.pressed ? 2 : 1
                            Column {
                                anchors.centerIn: parent
                                width: Math.max(0,parent.width-16)
                                spacing: 8
                                Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: screenBox.name; textFormat: Text.PlainText; color: theme.foreground; font.pixelSize: 17; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: screenBox.logicalWidth + " × " + screenBox.logicalHeight; textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 11; elide: Text.ElideRight }
                                Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: screenBox.posX + ", " + screenBox.posY; textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 11; elide: Text.ElideRight }
                            }
                            MouseArea {
                                id: dragger
                                objectName: "monitorDrag-" + screenBox.name
                                anchors.fill: parent
                                enabled: !root.busy
                                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                preventStealing: true
                                property point origin
                                property int startX
                                property int startY
                                onPressed: function(mouse) {
                                    root.selected=screenBox.index
                                    origin=mapToItem(canvas,mouse.x,mouse.y)
                                    startX=screenBox.posX;startY=screenBox.posY
                                }
                                onPositionChanged: function(mouse) {
                                    if (!pressed) return
                                    const current=mapToItem(canvas,mouse.x,mouse.y)
                                    const next=root.snap(screenBox.index,startX+(current.x-origin.x)/root.viewScale,startY+(current.y-origin.y)/root.viewScale)
                                    root.setPosition(screenBox.index,next.x,next.y)
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Button { text: strings.t("Fit"); onClicked: root.fit() }
                    Button { text: strings.t("Automatic row"); enabled: root.ready && !root.busy; onClicked: root.automaticRow() }
                    Button { text: strings.t("Saved layout"); enabled: root.ready && !root.busy && root.snapshot && root.snapshot.saved; onClicked: root.savedLayout() }
                    Item { Layout.fillWidth: true }
                    CheckBox { text: strings.t("Snap edges"); checked: root.snapEdges; onToggled: root.snapEdges=checked }
                }
            }
            Rectangle {
                Layout.preferredWidth: 264
                Layout.fillHeight: true
                color: theme.panel
                ScrollView {
                    id: detailsScroll
                    anchors.fill: parent
                    anchors.margins: 18
                    clip: true
                    contentWidth: availableWidth
                    contentHeight: detailsColumn.implicitHeight
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    id: detailsColumn
                    width: detailsScroll.availableWidth
                    spacing: 10
                    Label { text: strings.t("Selected display"); textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 12 }
                    Label { Layout.fillWidth: true; text: root.selectedMonitor ? root.selectedMonitor.name : strings.t("No display selected"); textFormat: Text.PlainText; color: theme.foreground; font.pixelSize: 22; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Label { Layout.fillWidth: true; text: root.selectedMonitor ? root.selectedMonitor.description : ""; textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 12; wrapMode: Text.WrapAnywhere }
                    Label { Layout.fillWidth: true; text: root.selectedMonitor ? root.selectedMonitor.pixelWidth + " × " + root.selectedMonitor.pixelHeight + " · " + root.selectedMonitor.displayScale + "×" : ""; textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 12 }
                    RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            Layout.fillWidth: true
                            enabled: !!root.selectedMonitor && !root.busy
                            placeholderText: "X"
                            text: root.selectedMonitor ? String(root.selectedMonitor.posX) : ""
                            validator: IntValidator { bottom: -65536; top: 65536 }
                            onEditingFinished: if (acceptableInput && root.selectedMonitor) root.setPosition(root.selected,Number(text),root.selectedMonitor.posY)
                        }
                        TextField {
                            Layout.fillWidth: true
                            enabled: !!root.selectedMonitor && !root.busy
                            placeholderText: "Y"
                            text: root.selectedMonitor ? String(root.selectedMonitor.posY) : ""
                            validator: IntValidator { bottom: -65536; top: 65536 }
                            onEditingFinished: if (acceptableInput && root.selectedMonitor) root.setPosition(root.selected,root.selectedMonitor.posX,Number(text))
                        }
                    }
                    Label { Layout.fillWidth: true; text: strings.t("Coordinates use logical pixels; negative Y places a screen higher."); textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap }
                    Label { text: strings.t("Align vertically"); textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 12 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Button { Layout.fillWidth: true; Layout.minimumWidth: 0; leftPadding: 8; rightPadding: 8; font.pixelSize: 12; text: strings.t("Top"); enabled: root.ready && !root.busy; onClicked: root.align("top") }
                        Button { Layout.fillWidth: true; Layout.minimumWidth: 0; leftPadding: 8; rightPadding: 8; font.pixelSize: 12; text: strings.t("Center"); enabled: root.ready && !root.busy; onClicked: root.align("center") }
                        Button { Layout.fillWidth: true; Layout.minimumWidth: 0; leftPadding: 8; rightPadding: 8; font.pixelSize: 12; text: strings.t("Bottom"); enabled: root.ready && !root.busy; onClicked: root.align("bottom") }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(theme.foreground.r,theme.foreground.g,theme.foreground.b,0.1) }
                    Label { text: strings.t("Connected displays"); textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 12 }
                    Repeater {
                        model: monitors
                        delegate: Button {
                            required property int index
                            required property string name
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            Layout.minimumHeight: 38
                            text: name
                            highlighted: root.selected === index
                            onClicked: root.selected=index
                            contentItem: Label { text: parent.text; textFormat: Text.PlainText; color: theme.foreground; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Label { text: strings.t("Saved profiles") + ": " + (root.snapshot ? root.snapshot.profiles : 0); textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 12 }
                }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { Layout.fillWidth: true; text: root.overlapping ? strings.t("Screens overlap. Move them apart before saving.") : root.message; textFormat: Text.PlainText; color: root.error || root.overlapping ? "#f2a89c" : theme.muted; wrapMode: Text.WordWrap; font.pixelSize: 12 }
                Label { Layout.fillWidth: true; text: root.snapshot ? root.snapshot.path : ""; textFormat: Text.PlainText; color: theme.muted; font.pixelSize: 10; elide: Text.ElideMiddle }
            }
            Label { text: strings.t(root.dirty ? "Unsaved changes" : "No changes"); textFormat: Text.PlainText; color: root.dirty ? theme.accent : theme.muted; font.pixelSize: 12 }
        }
    }

    }

    Dialog {
        id: discardDialog
        parent: root.contentItem
        anchors.centerIn: parent
        modal: true
        title: strings.t("Discard changes?")
        ColumnLayout {
            Label { text: strings.t("Your unsaved arrangement will be lost."); textFormat: Text.PlainText }
            RowLayout {
                Button { text: strings.t("Cancel"); onClicked: discardDialog.close() }
                Button {
                    text: strings.t("Discard")
                    onClicked: {
                        root.dirty=false
                        discardDialog.close()
                        if(root.pendingDiscard === "quit") Qt.quit()
                        else root.reload()
                    }
                }
            }
        }
    }
}
