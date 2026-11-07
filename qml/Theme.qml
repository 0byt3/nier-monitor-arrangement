import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    readonly property var colors: {
        const result = {background: "#171a20", foreground: "#e5e7eb", accent: "#a6c8ff"}
        const raw = palette.text()
        const lines = raw.split("\n")
        for (let line of lines) {
            const match = line.match(/^\s*(background|foreground|accent)\s*=\s*["'](#[0-9a-fA-F]{6})["']/)
            if (match) result[match[1]] = match[2]
        }
        return result
    }
    readonly property color background: colors.background
    readonly property color foreground: colors.foreground
    readonly property color accent: colors.accent
    readonly property color panel: Qt.lighter(background, 1.35)
    readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.65)
    property FileView palette: FileView {
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
    }
}
