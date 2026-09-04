pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Hyprland
import qs.services
import qs.modules.common

Item {
    id: workspaces

    property string screenName: ""
    property real s: 1
    property real stickW: 17 * s
    property real dotW: 5 * s
    property real gap: 4 * s

    property int hoverIndex: -1
    
    // Le média reste affiché par défaut
readonly property bool showMedia: hasPlayer
    // État temporaire pour le switch de workspace
    property bool workspaceSwitchActive: false

    // Timer de sécurité strict pour être sûr que ça ne reste jamais bloqué
    Timer {
        id: switchUnlockTimer
        interval: 2600 // Durée de l'animation de switch
        running: false
        onTriggered: {
            workspaces.workspaceSwitchActive = false;
        }
    }

    MouseArea {
        z: 999
        anchors.fill: parent
        enabled: workspaces.workspaceSwitchActive
        // En ne mettant pas de curseur particulier et en acceptant les événements, 
        // cela empêche la souris de cliquer à travers tant que l'animation n'est pas finie.
        acceptedButtons: Qt.AllButtons
        onPressed: (mouse) => mouse.accepted = true
        onClicked: (mouse) => mouse.accepted = true
    }

    // ==========================================
    // DONNÉES MÉDIAS (SÉCURISÉES VIA PillPlayers)
    // ==========================================
    readonly property var activePlayer: (typeof PillPlayers !== "undefined") ? PillPlayers.active : null
    readonly property bool hasPlayer: (typeof PillPlayers !== "undefined") ? PillPlayers.has : false
    readonly property bool playing: (typeof PillPlayers !== "undefined") ? PillPlayers.playing : false

    readonly property string currentTitle: (typeof PillPlayers !== "undefined" && PillPlayers.title) ? PillPlayers.title : "Rien en lecture"
    readonly property string currentArtist: (typeof PillPlayers !== "undefined" && PillPlayers.artist) ? PillPlayers.artist : ""
    readonly property string currentCoverUrl: (typeof PillPlayers !== "undefined" && PillPlayers.artUrl) ? PillPlayers.artUrl : ""

    readonly property real lengthSec: (typeof PillPlayers !== "undefined") ? PillPlayers.lengthSec : 0
    readonly property real positionSec: (hasPlayer && activePlayer && activePlayer.position) ? activePlayer.position : 0
    readonly property bool isLive: (typeof PillPlayers !== "undefined") ? PillPlayers.live : false

    function fmtTime(sec) {
        if (!(sec > 0)) return "0:00";
        var t = Math.floor(sec);
        var m = Math.floor(t / 60);
        var ss = t % 60;
        return m + ":" + (ss < 10 ? "0" + ss : ss);
    }

    Timer {
        interval: 500
        running: workspaces.showMedia && workspaces.playing && !workspaces.workspaceSwitchActive
        repeat: true
        onTriggered: if (workspaces.activePlayer && workspaces.activePlayer.positionChanged) workspaces.activePlayer.positionChanged()
    }

    // Déclenchement propre du switch de workspace
    onActiveIndexChanged: {
        workspaceSwitchActive = true;
        switchUnlockTimer.restart();
    }

    readonly property var slots: {
        if (CompositorService.isNiri) {
            const all = NiriService.allWorkspaces ?? [];
            const mine = all
                .filter(w => !workspaces.screenName || w.output === workspaces.screenName)
                .sort((a, b) => a.idx - b.idx);
            const trimmed = mine.filter((w, i) =>
                !(i === mine.length - 1 && !w.is_focused && !w.active_window_id));
            return trimmed.map(w => ({ key: w.idx, active: w.is_focused === true }));
        }

        const out = [];
        const seen = ({});
        const wss = Hyprland.workspaces?.values ?? [];
        for (let i = 0; i < wss.length; i++) {
            const w = wss[i];
            if (w.id >= 1 && w.monitor && w.monitor.name === workspaces.screenName && !seen[w.id]) {
                seen[w.id] = true;
                out.push(w.id);
            }
        }
        out.sort((x, y) => x - y);

        const activeId = workspaces.hyprActiveId;
        if (activeId >= 1 && !seen[activeId])
            out.push(activeId);
        return out.map(id => ({ key: id, active: id === activeId }));
    }

    readonly property int hyprActiveId: {
        if (CompositorService.isNiri) return -1;
        const mons = Hyprland.monitors?.values ?? [];
        for (let i = 0; i < mons.length; i++)
            if (mons[i].name === workspaces.screenName)
                return mons[i].activeWorkspace ? mons[i].activeWorkspace.id : -1;
        return -1;
    }

    readonly property int activeIndex: slots.findIndex(sl => sl.active)

    function focusSlot(key) {
        if (CompositorService.isNiri)
            NiriService.switchToWorkspace(key);
        else
            Hyprland.dispatch("workspace " + key);
    }

    function slotCenterX(idx) {
        if (showMedia && !workspaceSwitchActive) return width / 2;
        let x = 0;
        for (let i = 0; i < idx; i++)
            x += (i === activeIndex ? stickW : dotW) + gap;
        return x + (idx === activeIndex ? stickW : dotW) / 2;
    }

    readonly property point activeDotPoint: {
        void workspaces.activeIndex;
        void workspaces.width;
        return Qt.point(slotCenterX(Math.max(0, activeIndex)), height / 2);
    }

    implicitWidth: (showMedia && !workspaceSwitchActive) ? stepContent.implicitWidth : row.implicitWidth
    implicitHeight: (showMedia && !workspaceSwitchActive) ? stepContent.implicitHeight : row.implicitHeight

    Behavior on implicitWidth {
        NumberAnimation { duration: PillMotion.normal; easing.type: PillMotion.easeStandard }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: PillMotion.normal; easing.type: PillMotion.easeStandard }
    }

    // 1. WORKSPACES
    RowLayout {
        id: row
        visible: !workspaces.showMedia || workspaces.workspaceSwitchActive
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: workspaces.gap

        Repeater {
            model: workspaces.slots
            delegate: Item {
                id: slot
                required property var modelData
                required property int index
                readonly property bool isActive: slot.modelData.active

                Layout.preferredWidth: slot.isActive ? workspaces.stickW : workspaces.dotW
                Layout.preferredHeight: 22 * workspaces.s
                Behavior on Layout.preferredWidth {
                    NumberAnimation { duration: PillMotion.fast; easing.type: PillMotion.easeStandard }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: workspaces.dotW
                    radius: height / 2
                    color: slot.isActive ? PillTheme.vermLit : PillTheme.cream
                    opacity: slot.isActive ? 1.0 : (area.containsMouse ? 0.7 : 0.3)
                    Behavior on opacity { NumberAnimation { duration: PillMotion.fast } }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.leftMargin: -workspaces.gap / 2
                    anchors.rightMargin: -workspaces.gap / 2
                    anchors.topMargin: -8 * workspaces.s
                    anchors.bottomMargin: -8 * workspaces.s
                    hoverEnabled: true
                    // Empêche de cliquer ou de survoler pendant que l'animation du switch tourne
                    enabled: !workspaces.workspaceSwitchActive 
                    cursorShape: Qt.PointingHandCursor
                    onClicked: workspaces.focusSlot(slot.modelData.key)
                    onContainsMouseChanged: {
                        if (containsMouse)
                            workspaces.hoverIndex = slot.index;
                        else if (workspaces.hoverIndex === slot.index)
                            workspaces.hoverIndex = -1;
                    }
                }
            }
        }
    }

    // 2. BLOC MÉDIA AGRANDI
    Item {
        id: stepContent
        visible: workspaces.showMedia && !workspaces.workspaceSwitchActive
        implicitWidth: innerContent.implicitWidth + 20 * workspaces.s
        implicitHeight: 57 * workspaces.s

        anchors.verticalCenter: parent.verticalCenter
        clip: true

        Rectangle {
            id: backgroundMask
            anchors.fill: parent
            radius: 18 * workspaces.s
            color: "#000000"
            clip: true

            Image {
                id: bgCover
                anchors.fill: parent
                source: workspaces.currentCoverUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
                opacity: 0.4
            }

            Rectangle {
                width: parent.width * 0.3
                height: parent.height
                anchors.left: parent.left
                color: "transparent"
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#000000" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                width: parent.width * 0.3
                height: parent.height
                anchors.right: parent.right
                color: "transparent"
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#000000" }
                }
            }
        }

        Row {
            id: innerContent
            spacing: 10 * workspaces.s
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 1 * workspaces.s

            Item {
                id: coverContainer
                width: 35 * workspaces.s
                height: 35 * workspaces.s
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    id: innerCoverImg
                    anchors.fill: parent
                    source: workspaces.currentCoverUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                    asynchronous: true
                }

                OpacityMask {
                    anchors.fill: innerCoverImg
                    source: innerCoverImg
                    maskSource: Rectangle {
                        width: innerCoverImg.width
                        height: innerCoverImg.height
                        radius: 9 * workspaces.s
                    }
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    width: 15 * workspaces.s
                    height: 15 * workspaces.s
                    name: "music"
                    color: PillTheme.subtle ?? "lightgray"
                    visible: workspaces.currentCoverUrl === ""
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * workspaces.s

                Item {
                    id: titleContainer
                    width: 95 * workspaces.s
                    height: 15 * workspaces.s
                    clip: true

                    Text {
                        id: titleText
                        text: workspaces.currentTitle
                        color: PillTheme.cream ?? "white"
                        font.pixelSize: 12 * workspaces.s
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                        x: 0

                        readonly property real maxScroll: Math.max(0, titleText.implicitWidth - titleContainer.width)
                        readonly property bool needsScroll: maxScroll > 0

                        NumberAnimation on x {
                            id: titleScrollAnim
                            running: false
                            from: 0
                            to: -titleText.maxScroll
                            duration: Math.max(1000, titleText.maxScroll * 35)
                            easing.type: Easing.Linear
                            onFinished: titleResetTimer.restart()
                        }

                        Timer {
                            id: titleStartTimer
                            interval: 1500
                            running: workspaces.showMedia && !workspaces.workspaceSwitchActive && titleText.needsScroll
                            repeat: false
                            onTriggered: titleScrollAnim.restart()
                        }

                        Timer {
                            id: titleResetTimer
                            interval: 1200
                            onTriggered: {
                                titleText.x = 0;
                                titleStartTimer.restart();
                            }
                        }

                        onTextChanged: {
                            titleScrollAnim.stop();
                            titleText.x = 0;
                            if (needsScroll) titleStartTimer.restart();
                        }
                    }
                }

                Row {
                    spacing: 5 * workspaces.s

                    Item {
                        id: artistContainer
                        width: 60 * workspaces.s
                        height: 13 * workspaces.s
                        clip: true
                        visible: workspaces.currentArtist.length > 0

                        Text {
                            id: artistText
                            text: workspaces.currentArtist
                            color: "white"
                            opacity: 1.0
                            font.pixelSize: 8.5 * workspaces.s
                            anchors.verticalCenter: parent.verticalCenter
                            x: 0

                            readonly property real maxScroll: Math.max(0, artistText.implicitWidth - artistContainer.width)
                            readonly property bool needsScroll: maxScroll > 0

                            NumberAnimation on x {
                                id: artistScrollAnim
                                running: false
                                from: 0
                                to: -artistText.maxScroll
                                duration: Math.max(1000, artistText.maxScroll * 35)
                                easing.type: Easing.Linear
                                onFinished: artistResetTimer.restart()
                            }

                            Timer {
                                id: artistStartTimer
                                interval: 1800
                                running: workspaces.showMedia && !workspaces.workspaceSwitchActive && artistText.needsScroll
                                repeat: false
                                onTriggered: artistScrollAnim.restart()
                            }

                            Timer {
                                id: artistResetTimer
                                interval: 1200
                                onTriggered: {
                                    artistText.x = 0;
                                    artistStartTimer.restart();
                                }
                            }

                            onTextChanged: {
                                artistScrollAnim.stop();
                                artistText.x = 0;
                                if (needsScroll) artistStartTimer.restart();
                            }
                        }
                    }

                    Text {
                        text: workspaces.isLive ? "• Live" : (workspaces.hasPlayer ? workspaces.fmtTime(workspaces.positionSec) : "")
                        color: "white"
                        font.pixelSize: 9.5 * workspaces.s
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Row {
                spacing: 7 * workspaces.s
                anchors.verticalCenter: parent.verticalCenter

                GlyphIcon {
                    width: 20 * workspaces.s
                    height: 20 * workspaces.s
                    name: "prev"
                    color: "white"
                    opacity: (workspaces.hasPlayer && workspaces.activePlayer && workspaces.activePlayer.canGoPrevious) ? 1.0 : 0.4
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -5 * workspaces.s
                        hoverEnabled: true
                        enabled: workspaces.hasPlayer && workspaces.activePlayer && workspaces.activePlayer.canGoPrevious
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (workspaces.activePlayer && workspaces.activePlayer.previous)
                                workspaces.activePlayer.previous();
                        }
                    }
                }

                Rectangle {
                    width: 22 * workspaces.s
                    height: 22 * workspaces.s
                    radius: 5 * workspaces.s
                    color: playMouse.containsMouse ? PillTheme.verm : PillTheme.tileBg
                    anchors.verticalCenter: parent.verticalCenter

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 14 * workspaces.s
                        height: 14 * workspaces.s
                        name: workspaces.playing ? "pause" : "play"
                        color: "white"
                    }

                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        anchors.margins: -3 * workspaces.s
                        hoverEnabled: true
                        enabled: workspaces.hasPlayer && workspaces.activePlayer && workspaces.activePlayer.canTogglePlaying
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (workspaces.activePlayer && workspaces.activePlayer.togglePlaying)
                                workspaces.activePlayer.togglePlaying();
                        }
                    }
                }

                GlyphIcon {
                    width: 20 * workspaces.s
                    height: 20 * workspaces.s
                    name: "next"
                    color: "white"
                    opacity: (workspaces.hasPlayer && workspaces.activePlayer && workspaces.activePlayer.canGoNext) ? 1.0 : 0.4
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -5 * workspaces.s
                        hoverEnabled: true
                        enabled: workspaces.hasPlayer && workspaces.activePlayer && workspaces.activePlayer.canGoNext
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (workspaces.activePlayer && workspaces.activePlayer.next)
                                workspaces.activePlayer.next();
                        }
                    }
                }
            }
        }
    }

    // MouseArea pour le lecteur multimédia normal (actif uniquement hors switch)
    MouseArea {
        z: -1
        anchors.fill: parent
        enabled: workspaces.showMedia && !workspaces.workspaceSwitchActive
        hoverEnabled: !workspaces.workspaceSwitchActive
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (typeof pill !== "undefined" && pill.requestSurface) {
                pill.requestSurface("media");
            }
        }
        onContainsMouseChanged: {
            if (containsMouse) workspaces.hoverIndex = 0;
            else workspaces.hoverIndex = -1;
        }
    }
}