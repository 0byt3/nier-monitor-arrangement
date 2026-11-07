import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    readonly property string language: languageFile.text().trim() || "en"
    readonly property var catalog: {
        try { return JSON.parse(catalogFile.text() || "{}") } catch (error) { return ({}) }
    }
    function t(text) { return catalog[text] || text }
    property FileView languageFile: FileView {
        path: Quickshell.env("HOME") + "/.config/omarchy/language"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
    }
    property FileView catalogFile: FileView {
        path: Qt.resolvedUrl("i18n/" + root.language.split("-")[0] + ".json")
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
    }
}
