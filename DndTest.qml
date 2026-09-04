// Test ISOLÉ, à lancer à part (pas dans dynamisland/) :
//   quickshell -p DndTest.qml
// Bande verte en haut de l'écran principal, plein input region tout le temps
// (pas d'autoHide, pas de ghost mode, pas de mask dynamique). Glisse un
// fichier dessus :
//   - la bande passe au rouge + logs "ENTERED"/"DROPPED" dans le terminal
//     -> le DnD marche au niveau Quickshell/Hyprland, le souci vient de
//        la logique de mask/autoHide dans PillBar.qml
//   - rien ne se passe du tout
//     -> les surfaces wlr-layer-shell ne reçoivent pas le DnD sur ta config
//        actuelle (limite compositeur, pas un bug dans le QML)

import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    PanelWindow {
        id: win
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dnd-test"
        anchors { top: true; left: true; right: true }
        implicitHeight: 120
        color: "transparent"
        exclusiveZone: 0

        Rectangle {
            anchors.fill: parent
            color: dropArea.containsDrag ? "#cc0000" : "#00aa55"

            Text {
                anchors.centerIn: parent
                color: "white"
                font.pixelSize: 20
                text: dropArea.containsDrag ? "DROP ICI (containsDrag = true)" : "Glisse un fichier ici"
            }

            DropArea {
                id: dropArea
                anchors.fill: parent
                onEntered: (drag) => console.log("ENTERED, hasUrls =", drag.hasUrls)
                onExited: console.log("EXITED")
                onPositionChanged: (drag) => console.log("MOVE", drag.x, drag.y)
                onDropped: (drop) => {
                    console.log("DROPPED, hasUrls =", drop.hasUrls, "urls =", drop.urls)
                    drop.accept()
                }
            }
        }
    }
}
