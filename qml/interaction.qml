import QtQuick
import QtTest as Test
import Quickshell
import "Demo.js" as Demo

ShellRoot {
    Editor { id: editor; demoSnapshot: Demo.snapshot() }
    Test.TestEvent { id: events }
    function find(item, name) {
        if (item.objectName === name) return item
        if (!item.children) return null
        for (const child of item.children) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    Timer {
        interval: 700; running: true
        onTriggered: {
            try {
                const dragger = find(editor.contentItem, "monitorDrag-DP-2")
                if (!dragger) throw new Error("missing draggable display")
                const before = editor.positions()[1].y
                editor.snapEdges = false
                const x = dragger.width/2, y = dragger.height/2
                if (!events.mousePress(dragger,x,y,Qt.LeftButton,Qt.NoModifier,0)) throw new Error("mouse press failed")
                if (!events.mouseMove(dragger,x,y-30,10,Qt.LeftButton,Qt.NoModifier)) throw new Error("mouse move failed")
                events.mouseRelease(dragger,x,y-30,Qt.LeftButton,Qt.NoModifier,0)
                const after = editor.positions()[1].y
                if (after >= before || !editor.dirty) throw new Error("drag did not update vertical position")
                editor.automaticRow()
                if (editor.overlapping || editor.positions()[0].y !== 0 || editor.positions()[2].x !== 4000) throw new Error("automatic row failed")
                editor.align("bottom")
                if (editor.positions()[0].y + 1440 !== editor.positions()[1].y + 2560) throw new Error("bottom alignment failed")
                console.info("PASS: real pointer drag updates Y, automatic row and bottom alignment")
            } catch (error) { console.error("FAIL: " + error) }
            Qt.quit()
        }
    }
}
