pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import qs
import qs.services
import qs.modules.common

Item {
    id: pill

    property real s: 1
    property string screenName: ""
    property var barWindow
    property string surface: ""

    property bool hovered: false
    property bool pinned: false
    property bool forcePinned: false

    readonly property bool held: pinned || forcePinned
    readonly property bool surfaceOpen: surface.length > 0
    property bool hoverLatch: false

// In Pill.qml line 69
readonly property bool barMode: !!(Config.options?.bar?.pill?.barMode)   
 readonly property bool expanded: surfaceOpen || held || hoverLatch || barMode

    readonly property bool hasMedia: PillPlayers.has

    signal requestSurface(string name)
    signal requestClose()

    signal trayMenuRequested(var item, real anchorX)
    property bool trayMenuOpen: false

    readonly property real restW: 130 * s
    readonly property real restH: 38 * s
    readonly property real hoverPad: 20 * s
    readonly property real hoverW: hoverRow.implicitWidth + 2 * hoverPad
    readonly property real hoverH: 58 * s
    readonly property real gameH: 34 * s
    readonly property real gameW: barWindow ? barWindow.width : 1920

    readonly property real restCorner: PillTheme.cardCorner * s
    readonly property real openCorner: PillTheme.openCorner * s

    readonly property real powerW: 330 * s
    readonly property real powerH: 150 * s
    readonly property real mediaW: (PillPlayers.pickable.length > 1 ? 460 : 390) * s
    readonly property real mediaH: 150 * s
    readonly property real batteryW: 316 * s
    readonly property real toastW: 342 * s
    readonly property real sysmonW: 392 * s
    readonly property real clipboardW: 360 * s
    readonly property real clipboardH: 332 * s
    readonly property real glanceW: 470 * s
    readonly property real glanceH: 178 * s
    readonly property real launcherW: 360 * s
    readonly property real launcherH: 332 * s
    readonly property real recorderW: 330 * s
    readonly property real recorderH: 176 * s

    /**
     * LocalSend face.
     */
    property bool lsDragActive: false
    readonly property bool lsActive: !surfaceOpen && (lsDragActive || PillLocalsend.state !== "idle" || PillLocalsend.manualMode)
    readonly property int lsGridCols: 4
    readonly property int lsGridRows: 3
    readonly property real lsCellW: 92 * s
    readonly property real lsCellH: 54 * s
    readonly property real lsGridSpacing: 10 * s
    readonly property real lsPad: 18 * s
    readonly property real lsHeaderH: 22 * s
    readonly property real localsendW: lsPad * 2 + lsGridCols * lsCellW + (lsGridCols - 1) * lsGridSpacing
    readonly property real localsendH: lsPad * 2 + lsHeaderH + 8 * s + lsGridRows * lsCellH + (lsGridRows - 1) * lsGridSpacing

    readonly property bool sysmonEnabled: Config.options?.bar?.pill?.surfaces?.sysmon ?? true
    readonly property bool clipboardEnabled: Config.options?.bar?.pill?.surfaces?.clipboard ?? true
    readonly property bool glanceEnabled: Config.options?.bar?.pill?.surfaces?.glance ?? true
    readonly property bool launcherEnabled: Config.options?.bar?.pill?.surfaces?.launcher ?? true
    readonly property bool recorderEnabled: Config.options?.bar?.pill?.surfaces?.recorder ?? false
    readonly property bool localsendEnabled: Config.options?.bar?.pill?.surfaces?.localsend ?? true

    readonly property var hoverModules: Config.options?.bar?.pill?.modules
    readonly property real iconPx: Math.round((Config.options?.bar?.pill?.iconSize ?? 17) * s)

    function outputEnabled(list: var): bool {
        if (!list || list.length === 0)
            return true
        if (screenName.length > 0 && list.includes(screenName))
            return true
        const currentNames = Quickshell.screens.map(screen => screen?.name ?? "")
        return !list.some(name => currentNames.includes(name))
    }

    readonly property bool toastOutputEnabled: pill.outputEnabled(Config.options?.notifications?.screenList ?? [])
    readonly property bool osdOutputEnabled: pill.outputEnabled(Config.options?.osd?.screenList ?? [])
    readonly property bool toastActive: (Config.options?.bar?.pill?.toasts ?? true)
        && pill.toastOutputEnabled && PillNotifs.popups.length > 0
    readonly property bool osdActive: pill.osdOutputEnabled && osd.flashing
    readonly property bool compactAnnounces: Config.options?.bar?.pill?.compactAnnounces ?? false

    property int resizeNonce: 0
    property var primedLoaders: ({})
    property bool suppressHoverExpand: false
    function surfaceItem(ld) {
        const wasActive = ld.active;
        ld.active = true;
        if (!wasActive && !primedLoaders[ld]) {
            primedLoaders[ld] = true;
            resizeRelayoutTimer.restart();
        }
        return ld.item;
    }

    Timer {
        id: resizeRelayoutTimer
        interval: 32
        repeat: false
        onTriggered: pill.resizeNonce++
    }

    readonly property var surfaces: ({
        power:    { size: () => { surfaceItem(ldPower); return Qt.size(powerW, powerH); }, ame: () => surfaceItem(ldPower) },
        media:    { size: () => { surfaceItem(ldMedia); return Qt.size(mediaW, mediaH); }, ame: () => surfaceItem(ldMedia) },
        battery:  { size: () => Qt.size(batteryW, surfaceItem(ldBattery).implicitHeight + 26 * s), ame: () => surfaceItem(ldBattery) },
        calendar: { size: () => { const it = surfaceItem(ldCalendar); return Qt.size((it.implicitWidth > 0 ? it.implicitWidth : 282 * s) + 36 * s, it.implicitHeight + 32 * s); }, ame: () => surfaceItem(ldCalendar) },
        link:     { size: () => { const it = surfaceItem(ldLink); return Qt.size(it.desiredW, it.implicitHeight + 26 * s); }, ame: () => surfaceItem(ldLink) },
        mixer:    { size: () => Qt.size(93 * Math.max(4, surfaceItem(ldMixer).faderCount) * s, mixerH), ame: () => surfaceItem(ldMixer) },
        sysmon:   { size: () => Qt.size(sysmonW, surfaceItem(ldSysmon).implicitHeight + 33 * s), ame: () => surfaceItem(ldSysmon) },
        clipboard: { size: () => { surfaceItem(ldClipboard); return Qt.size(clipboardW, clipboardH); }, ame: () => surfaceItem(ldClipboard) },
        glance:   { size: () => { surfaceItem(ldGlance); return Qt.size(glanceW, glanceH); }, ame: () => surfaceItem(ldGlance) },
        launcher: { size: () => { surfaceItem(ldLauncher); return Qt.size(launcherW, launcherH); }, ame: () => surfaceItem(ldLauncher) },
        recorder: { size: () => { surfaceItem(ldRecorder); return Qt.size(recorderW, recorderH); }, ame: () => surfaceItem(ldRecorder) }
    })

    readonly property real mixerH: 214 * s

    property string linkInitialView: "main"
    onSurfaceChanged: if (surface !== "link") linkInitialView = "main"

    readonly property bool manualGameFace: GameMode.manuallyActivated

    readonly property bool fsCovered: {
        if (!CompositorService.isNiri)
            return GameMode.hasAnyFullscreenWindow;
        const wins = NiriService.windows ?? [];
        for (const w of wins) {
            const ws = NiriService.workspaces?.[w.workspace_id];
            if (!(ws?.is_active ?? false))
                continue;
            if (screenName.length > 0 && ws.output !== screenName)
                continue;
            if (!w.is_focused)
                continue;
            if (GameMode.isWindowFullscreen(w))
                return true;
        }
        return false;
    }
    readonly property bool fsHide: fsCovered
        && (mode === "rest" || mode === "hover" || mode === "game")

    opacity: fsHide ? 0 : 1
    visible: opacity > 0.01
    Behavior on opacity {
        NumberAnimation { duration: PillMotion.standard; easing.type: PillMotion.easeStandard }
    }

    readonly property string mode: surfaceOpen && surfaces[surface] !== undefined ? surface
        : (lsActive ? "localsend"
        : (manualGameFace && !fsCovered ? "game"
        : (osdActive && !held ? "osd"
        : (toastActive && !held ? "toast"
        : (expanded ? "hover" : "rest")))))

    onSurfaceOpenChanged: {
        if (surfaceOpen) {
            pinned = false;
        } else {
            hoverLatch = false;
        }
    }

    QtObject {
        id: clock
        readonly property var loc: Qt.locale()
        readonly property var now: sysClock.date
        readonly property string timeFormat: (PillTheme.time12h ? "h:mm" : "HH:mm")
            + (PillTheme.clockSeconds ? ":ss" : "")
            + (PillTheme.time12h ? " AP" : "")
        readonly property string hhmm: Qt.formatTime(now, timeFormat)
        readonly property string date: loc.toString(now, "ddd d MMM")
    }

    SystemClock {
        id: sysClock
        precision: PillTheme.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    readonly property bool compactAnnounceMode: compactAnnounces && (mode === "osd" || mode === "toast")
    property real morphRadius: mode === "localsend"
        ? 32 * s
        : ((mode === "rest" || mode === "hover" || mode === "game" || compactAnnounceMode)
            ? restCorner : openCorner)

    readonly property var modeSize: ({
        hover: () => Qt.size(hoverW, hoverH),
        localsend: () => Qt.size(localsendW, localsendH),
        game: () => Qt.size(gameW, gameH),
        osd: () => compactAnnounces ? Qt.size(restW, restH) : Qt.size(osd.desiredW, osd.desiredH),
        toast: () => {
            if (compactAnnounces)
                return Qt.size(restW, restH);
            const th = toastLoader.item ? toastLoader.item.implicitHeight + 24 * s : restH;
            return Qt.size(toastW, th);
        }
    })

    readonly property size targetSize: {
        resizeNonce;
        const sf = surfaces[mode];
        if (sf)
            return sf.size();
        const f = modeSize[mode];
        return f ? f() : Qt.size(Math.max(restW, restRow.implicitWidth + 36 * s), restH);
    }

    readonly property real targetW: Math.round(targetSize.width / 2) * 2
    readonly property real targetH: Math.round(targetSize.height)

    width: targetW
    height: targetH

    readonly property real rawMorphCloseness: {
        const d = Math.max(Math.abs(width - targetW), Math.abs(height - targetH));
        return 1 - Math.min(1, d / (110 * s));
    }

    readonly property real morphCloseness: Math.max(0, Math.min(1, (rawMorphCloseness - 0.5) / 0.5))

    property bool hoverSoulGate: false
    readonly property bool hoverArrived: mode === "hover" && morphCloseness > 0.55
    onHoverArrivedChanged: if (hoverArrived) hoverSoulGate = true

    property string lastMode: "rest"
    property bool hoverHop: false

    onModeChanged: {
        hoverHop = (mode === "hover" || mode === "rest") && (lastMode === "hover" || lastMode === "rest");
        lastMode = mode;
        if (mode !== "hover") {
            hoverSoulGate = false;
            soulTarget = "";
            soulWsIndex = -1;
        }
    }
    onHoverSoulGateChanged: if (hoverSoulGate) kanjiFlashAnim.restart()

    property string soulTarget: ""
    property int soulWsIndex: -1
    property real kanjiFlash: 0

    SequentialAnimation {
        id: kanjiFlashAnim
        NumberAnimation { target: pill; property: "kanjiFlash"; to: 1; duration: Math.round(90 * PillMotion.mult); easing.type: Easing.OutCubic }
        NumberAnimation { target: pill; property: "kanjiFlash"; to: 0; duration: Math.round(320 * PillMotion.mult); easing.type: Easing.OutCubic }
    }

    Behavior on width { NumberAnimation { duration: pill.hoverHop ? 350 : PillMotion.morph; easing.type: PillMotion.easeMorph; easing.bezierCurve: PillMotion.morphCurve } }
    Behavior on height { NumberAnimation { duration: pill.hoverHop ? PillMotion.glide : PillMotion.morph; easing.type: PillMotion.easeMorph; easing.bezierCurve: PillMotion.morphCurve } }
    Behavior on morphRadius { NumberAnimation { duration: pill.hoverHop ? PillMotion.glide : PillMotion.morph; easing.type: PillMotion.easeMorph; easing.bezierCurve: PillMotion.morphCurve } }

    Rectangle {
        id: bud
        readonly property bool shown: false
        visible: false
        width: 0
        height: 0
    }

    Item {
        id: glass
        anchors.fill: parent
        z: -1

        readonly property bool active: pill.visible
            && PillTheme.islandGlass
            && Appearance.effectsEnabled
            && PillTheme.pillOpacity < 0.999

        visible: active
        layer.enabled: active
        layer.effect: GE.OpacityMask {
            maskSource: Rectangle {
                width: glass.width
                height: glass.height
                radius: body.radius
            }
        }

        Image {
            id: glassWallpaper
            x: -pill.x
            y: -pill.y
            width: pill.barWindow ? pill.barWindow.width : 1920
            height: pill.barWindow ? pill.barWindow.height : 1080
            visible: glass.active && status === Image.Ready
            source: glass.active ? Wallpapers.effectiveWallpaperUrl : ""
            fillMode: Image.PreserveAspectCrop
            cache: true
            asynchronous: true
            sourceSize.width: width
            sourceSize.height: height

            layer.enabled: glass.active
            layer.effect: MultiEffect {
                source: glassWallpaper
                anchors.fill: source
                saturation: 0.15
                blurEnabled: true
                blurMax: 64
                blur: PillTheme.islandGlassBlur
            }
        }
    }

    Rectangle {
        id: body
        anchors.fill: parent
        clip: true

        property real gameFlat: pill.mode === "game" ? 1 : 0
        Behavior on gameFlat { NumberAnimation { duration: PillMotion.morph; easing.type: PillMotion.easeMorph; easing.bezierCurve: PillMotion.morphCurve } }

        radius: pill.morphRadius
        topLeftRadius: pill.morphRadius * (1 - gameFlat)
        topRightRadius: pill.morphRadius * (1 - gameFlat)
        bottomLeftRadius: pill.morphRadius * (1 - gameFlat)
        bottomRightRadius: pill.morphRadius * (1 - gameFlat)
        border.width: 1
        border.color: "#1a1a1a"

        color: "#000000"

        layer.enabled: PillTheme.islandShadow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, PillTheme.shadowOpacity)
            shadowBlur: 0.7
            shadowVerticalOffset: 3 * pill.s
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: body.radius * 0.6
            anchors.rightMargin: body.radius * 0.6
            height: 1
            visible: PillTheme.islandSheen
            color: PillTheme.sheen
        }
    }

    readonly property point wakePoint: {
        void pill.width;
        void pill.height;
        return restKanji.mapToItem(pill, restKanji.width / 2, restKanji.height / 2);
    }

    readonly property point soulPoint: {
        void pill.width;
        void pill.height;
        const drop = 12 * pill.s;
        if (soulTarget === "wifi")
            return wifiIcon.mapToItem(pill, wifiIcon.width / 2, wifiIcon.height + drop * 0.55);
        if (soulTarget === "battery")
            return batteryIcon.mapToItem(pill, batteryIcon.width / 2, batteryIcon.height + drop * 0.55);
        if (soulTarget === "inbox")
            return inboxIcon.mapToItem(pill, inboxIcon.width / 2, inboxIcon.height + drop * 0.55);
        if (soulTarget === "mixer")
            return mixerIcon.mapToItem(pill, mixerIcon.width / 2, mixerIcon.height + drop * 0.55);
        if (soulTarget === "glance")
            return glanceIcon.mapToItem(pill, glanceIcon.width / 2, glanceIcon.height + drop * 0.55);
        if (soulTarget === "launcher")
            return launcherIcon.mapToItem(pill, launcherIcon.width / 2, launcherIcon.height + drop * 0.55);
        if (soulTarget === "recorder")
            return recorderIcon.mapToItem(pill, recorderIcon.width / 2, recorderIcon.height + drop * 0.55);
        if (soulTarget === "localsend")
            return localsendIcon.mapToItem(pill, localsendIcon.width / 2, localsendIcon.height + drop * 0.55);
        if (soulTarget === "power")
            return powerIcon.mapToItem(pill, powerIcon.width / 2, powerIcon.height + drop * 0.55);
        if (soulTarget === "clipboard")
            return clipboardIcon.mapToItem(pill, clipboardIcon.width / 2, clipboardIcon.height + drop * 0.55);
        if (soulTarget === "sysmon")
            return sysmonIcon.mapToItem(pill, sysmonIcon.width / 2, sysmonIcon.height + drop * 0.55);
        if (soulTarget === "sidebarLeft")
            return sidebarLeftIcon.mapToItem(pill, sidebarLeftIcon.width / 2, sidebarLeftIcon.height + drop * 0.55);
        if (soulTarget === "sidebarRight")
            return sidebarRightIcon.mapToItem(pill, sidebarRightIcon.width / 2, sidebarRightIcon.height + drop * 0.55);
        if (soulTarget === "ws" && soulWsIndex >= 0) {
            void ws.activeIndex;
            void ws.width;
            const p = ws.mapToItem(pill, ws.slotCenterX(soulWsIndex), ws.height / 2);
            return Qt.point(p.x, p.y + drop);
        }
        return ws.mapToItem(pill, ws.activeDotPoint.x, ws.activeDotPoint.y + drop);
    }

    readonly property var ameSurface: (surfaceOpen && surfaces[surface] !== undefined)
        ? surfaces[surface].ame() : null

    Ame {
        id: ame
        anchors.fill: parent
        s: pill.s
        wake: pill.wakePoint
        wickDir: -1
        form: pill.ameSurface ? pill.ameSurface.ameForm
            : (pill.mode === "hover" && pill.hoverSoulGate && (Config.options?.bar?.pill?.soul?.enable ?? true) ? "soul" : "off")
        point: pill.ameSurface
            ? Qt.point(pill.ameSurface.x + pill.ameSurface.amePoint.x,
                       pill.ameSurface.y + pill.ameSurface.amePoint.y)
            : (pill.mode === "hover" ? pill.soulPoint : pill.wakePoint)
    }

    readonly property real inputPadRight: bud.shown ? bud.budR + 2 * s : 0

    onHoveredChanged: {
        if (hovered) {
            if (!suppressHoverExpand) {
                if (PillPlayers.has) {
                    mediaExpandDelay.restart();
                } else {
                    hoverLatch = true;
                }
            }
            graceTimer.stop();
            graceRetries = 0;
        } else {
            mediaExpandDelay.stop();
            graceRetries = 0;
            graceTimer.restart();
        }
    }

    Timer {
        id: mediaExpandDelay
        interval: 250
        repeat: false
        onTriggered: {
            if (pill.hovered) {
                pill.hoverLatch = true;
            }
        }
    }

    property int graceRetries: 0

    Timer {
        id: graceTimer
        interval: 300
        onTriggered: {
            if (pill.morphCloseness < 0.95 && pill.graceRetries < 6) {
                pill.graceRetries++;
                graceTimer.restart();
                return;
            }
            pill.graceRetries = 0;
            pill.hoverLatch = false;
        }
    }

    TapHandler {
        enabled: !pill.surfaceOpen && !pill.barMode
        gesturePolicy: TapHandler.WithinBounds
        onTapped: pill.pinned = !pill.pinned
    }

    Item {
        id: gameBar
        anchors.fill: parent
        enabled: pill.mode === "game"
        opacity: pill.mode === "game" ? Math.pow(pill.morphCloseness, 1.2) : 0
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: PillMotion.standard; easing.type: PillMotion.easeStandard } }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 18 * pill.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9 * pill.s
            opacity: pill.hasMedia ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: PillMotion.standard; easing.type: PillMotion.easeStandard } }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 26 * pill.s
                height: 26 * pill.s
                radius: 7 * pill.s
                color: PillTheme.tileBg
                clip: true
                Image {
                    id: pillTrackArt
                    anchors.fill: parent
                    source: MprisController.activePlayer?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                    sourceSize.width: Math.max(1, Math.round(pillTrackArt.width * 2))
                    sourceSize.height: Math.max(1, Math.round(pillTrackArt.height * 2))
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: MprisController.activePlayer?.trackTitle ?? ""
                    color: PillTheme.cream
                    font.family: PillTheme.font
                    font.pixelSize: 12.5 * pill.s
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 220 * pill.s)
                }
                Text {
                    text: PillTheme.joinArtists(MprisController.activePlayer?.trackArtists,
                                                MprisController.activePlayer?.trackArtist)
                    color: PillTheme.dim
                    font.family: PillTheme.font
                    font.pixelSize: 10.5 * pill.s
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 220 * pill.s)
                    visible: text.length > 0
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: clock.hhmm
            color: PillTheme.cream
            font.family: PillTheme.font
            font.pixelSize: 16 * pill.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }

    /**
     * LocalSend face.
     */
    Item {
        id: lsFace
        anchors.fill: parent
        enabled: pill.mode === "localsend"
        opacity: pill.mode === "localsend" ? Math.pow(pill.morphCloseness, 0.6) : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: PillMotion.standard; easing.type: PillMotion.easeStandard } }

        readonly property bool preDrop: pill.lsDragActive && PillLocalsend.state === "idle" && PillLocalsend.pendingFile === ""
        readonly property int deviceCount: PillLocalsend.devices.count
        readonly property bool showGrid: !preDrop && PillLocalsend.lsSubMode === "send" && PillLocalsend.state === "ready" && deviceCount > 0

        DropArea {
            anchors.fill: parent
            enabled: PillLocalsend.lsSubMode === "send" || PillLocalsend.lsSubMode === "choose"
            onEntered: (drag) => {
                if (drag.hasUrls) pill.lsDragActive = true;
            }
            onExited: {
                pill.lsDragActive = false;
            }
            onDropped: (drop) => {
                pill.lsDragActive = false;
                if (!drop.hasUrls) return;
                const raw = drop.urls[0].toString().trim();
                const path = raw.startsWith("file://") ? decodeURIComponent(raw.substring(7)) : raw;
                PillLocalsend.openSendPicker(path);
                drop.accept();
            }
        }

        Item {
            id: lsBody
            anchors.fill: parent
            anchors.margins: pill.lsPad

            // Bouton de fermeture / annulation en haut à droite
            Rectangle {
                id: lsCloseBtn
                anchors.top: parent.top
                anchors.right: parent.right
                z: 10
                width: 22 * pill.s
                height: 22 * pill.s
                radius: width / 2
                color: lsCloseMouse.containsMouse ? "#333333" : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                GlyphIcon {
                    anchors.centerIn: parent
                    width: 12 * pill.s
                    height: 12 * pill.s
                    name: "close"
                    color: lsCloseMouse.containsMouse ? PillTheme.cream : PillTheme.dim
                    stroke: 1.8
                }

                MouseArea {
                    id: lsCloseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PillLocalsend.cancel()
                }
            }

            // --- VUE PRE-DROP (Pendant le survol drag&drop du fichier avant de relâcher) ---
            Item {
                id: preDropView
                anchors.fill: parent
                visible: lsFace.preDrop
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }

                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -15 * pill.s
                    spacing: 10 * pill.s

                    GlyphIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 28 * pill.s
                        height: 28 * pill.s
                        name: "send"
                        color: PillTheme.cream
                        stroke: 1.8
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Share with LocalSend"
                        color: PillTheme.cream
                        font.family: PillTheme.font
                        font.pixelSize: 17 * pill.s
                        font.weight: Font.Bold
                    }
                }
            }

            // --- VUE 1 : CHOIX (Envoyer / Recevoir) ---
            Item {
                id: chooseView
                anchors.fill: parent
                visible: !lsFace.preDrop && PillLocalsend.lsSubMode === "choose"
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }

                Column {
                    anchors.centerIn: parent
                    spacing: 16 * pill.s

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "LocalSend"
                        color: PillTheme.cream
                        font.family: PillTheme.font
                        font.pixelSize: 17 * pill.s
                        font.weight: Font.Bold
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 14 * pill.s

                        // Bouton ENVOYER (Gauche)
                        Rectangle {
                            width: 120 * pill.s
                            height: 52 * pill.s
                            radius: 12 * pill.s
                            color: sendBtnMouse.containsMouse ? "#2d3748" : PillTheme.tileBg
                            border.width: 1
                            border.color: sendBtnMouse.containsMouse ? PillTheme.cream : "#333333"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 3 * pill.s

                                GlyphIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 18 * pill.s
                                    height: 18 * pill.s
                                    name: "send"
                                    color: PillTheme.cream
                                    stroke: 1.6
                                }

                                Text {
                                    text: "Envoyer"
                                    color: PillTheme.cream
                                    font.family: PillTheme.font
                                    font.pixelSize: 12 * pill.s
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                id: sendBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: PillLocalsend.setSubMode("send")
                            }
                        }

                        // Bouton RECEVOIR (Droite)
                        Rectangle {
                            width: 120 * pill.s
                            height: 52 * pill.s
                            radius: 12 * pill.s
                            color: recvBtnMouse.containsMouse ? "#2d3748" : PillTheme.tileBg
                            border.width: 1
                            border.color: recvBtnMouse.containsMouse ? PillTheme.cream : "#333333"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 3 * pill.s

                                GlyphIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 18 * pill.s
                                    height: 18 * pill.s
                                    name: "inbox"
                                    color: PillTheme.cream
                                    stroke: 1.6
                                }

                                Text {
                                    text: "Recevoir"
                                    color: PillTheme.cream
                                    font.family: PillTheme.font
                                    font.pixelSize: 12 * pill.s
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                id: recvBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: PillLocalsend.setSubMode("receive")
                            }
                        }
                    }
                }
            }

            // --- VUE 2 : RECEVOIR ---
            Item {
                id: receiveView
                anchors.fill: parent
                anchors.verticalCenterOffset: -45 * pill.s
                visible: !lsFace.preDrop && PillLocalsend.lsSubMode === "receive"
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }

                // Icône principale : inbox (attente) / download-cloud (transfert) / check (reçu)
                readonly property string recvIcon: {
                    switch (PillLocalsend.recvState) {
                        case "transferring": return "download-cloud";
                        case "done":         return "check-circle";
                        default:             return "inbox";
                    }
                }
                readonly property color recvColor: {
                    switch (PillLocalsend.recvState) {
                        case "transferring": return "#60a5fa"; // bleu
                        case "done":         return "#4ade80"; // vert
                        default:             return PillTheme.cream;
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 10 * pill.s

                    // --- Icône animée ---
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 36 * pill.s
                        height: 36 * pill.s

                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 32 * pill.s
                            height: 32 * pill.s
                            name: receiveView.recvIcon
                            color: receiveView.recvColor
                            stroke: 1.8
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }

                        // Point pulsant sur l'icône en mode "waiting" (prêt à recevoir)
                        Rectangle {
                            visible: PillLocalsend.recvState === "waiting"
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: 1 * pill.s
                            anchors.topMargin: 1 * pill.s
                            width: 8 * pill.s
                            height: 8 * pill.s
                            radius: width / 2
                            color: "#4ade80"

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: PillLocalsend.recvState === "waiting"
                                NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    // --- Texte principal : état ---
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            switch (PillLocalsend.recvState) {
                                case "transferring":
                                    return PillLocalsend.recvSenderAlias.length > 0
                                        ? `Réception de "${PillLocalsend.recvSenderAlias}"`
                                        : "Receiving in progress…";
                                case "done":
                                    return PillLocalsend.recvSenderAlias.length > 0
                                        ? `Received from "${PillLocalsend.recvSenderAlias}"`
                                        : "Received !";
                                default:
                                    return "Waiting for files…";
                            }
                        }
                        color: receiveView.recvColor
                        font.family: PillTheme.font
                        font.pixelSize: 14 * pill.s
                        font.weight: Font.DemiBold
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }

                    // --- Sous-texte : nom du fichier ou hint ---
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: lsBody.width - 8 * pill.s
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        wrapMode: Text.NoWrap
                        text: {
                            if (PillLocalsend.recvState === "done" && PillLocalsend.recvLastFile.length > 0)
                                return PillLocalsend.recvLastFile;
                            if (PillLocalsend.recvState === "transferring" && PillLocalsend.recvLastFile.length > 0)
                                return PillLocalsend.recvLastFile;
                            return "LocalSend est prêt à recevoir";
                        }
                        color: PillLocalsend.recvState === "waiting" ? PillTheme.dim : PillTheme.subtle
                        font.family: PillTheme.font
                        font.pixelSize: 10.5 * pill.s
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }

                    // --- Barre de progression animée (visible pendant "transferring") ---
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 140 * pill.s
                        height: 3 * pill.s
                        radius: height / 2
                        color: "#1e293b"
                        visible: PillLocalsend.recvState === "transferring"
                        opacity: visible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        Rectangle {
                            id: progressBar
                            width: 0
                            height: parent.height
                            radius: parent.radius
                            color: "#60a5fa"

                            SequentialAnimation on width {
                                loops: Animation.Infinite
                                running: PillLocalsend.recvState === "transferring"
                                NumberAnimation { to: progressBar.parent.width * 0.85; duration: 1200; easing.type: Easing.InOutCubic }
                                NumberAnimation { to: progressBar.parent.width * 0.15; duration: 900;  easing.type: Easing.InOutCubic }
                            }
                        }
                    }
                }
            }

            // --- VUE 3 : ENVOYER ---
            Item {
                id: sendView
                anchors.fill: parent
                visible: !lsFace.preDrop && PillLocalsend.lsSubMode === "send"
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }

                Item {
                    id: lsHeader
                    width: parent.width
                    height: pill.lsHeaderH
                    x: 0
                    y: lsFace.showGrid ? 0 : (lsBody.height - height) / 2
                    Behavior on y {
                        NumberAnimation { duration: PillMotion.standard; easing.type: PillMotion.easeStandard }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2 * pill.s

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: (PillLocalsend.state === "scanning") ? "Searching…"
                                : (PillLocalsend.state === "sending") ? "Sending…"
                                : (lsFace.deviceCount > 0 ? "Send to :"
                                : (PillLocalsend.pendingFile.length > 0 ? "No devices found" : "Send with LocalSend"))
                            color: PillTheme.cream
                            font.family: PillTheme.font
                            font.pixelSize: 15 * pill.s
                            font.weight: Font.DemiBold
                        }

                        // Affiche "(drag file here)" SOUS le titre uniquement si lancé via le bouton et sans fichier drop
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: PillLocalsend.manualMode && PillLocalsend.pendingFile === "" && PillLocalsend.state === "idle"
                            text: "(drag file here)"
                            color: PillTheme.dim
                            font.family: PillTheme.font
                            font.pixelSize: 11.5 * pill.s
                            font.weight: Font.Normal
                        }
                    }
                }

                Grid {
                    id: lsGrid
                    anchors.top: lsHeader.bottom
                    anchors.topMargin: 8 * pill.s
                    anchors.left: parent.left
                    columns: pill.lsGridCols
                    rows: pill.lsGridRows
                    spacing: pill.lsGridSpacing
                    opacity: lsFace.showGrid ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: PillMotion.standard; easing.type: PillMotion.easeStandard } }

                    Repeater {
                        model: lsFace.showGrid ? PillLocalsend.devices : 0
                        delegate: Rectangle {
                            id: lsDevice
                            required property string alias
                            required property string ip
                            required property string deviceType

                            width: pill.lsCellW
                            height: pill.lsCellH
                            radius: 10 * pill.s
                            color: lsDevMouse.containsMouse ? "#2a2a2a" : PillTheme.tileBg
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 3 * pill.s

                                GlyphIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 20 * pill.s
                                    height: 20 * pill.s
                                    stroke: 1.5
                                    color: lsDevMouse.containsMouse ? PillTheme.cream : PillTheme.subtle
                                    
                                    name: {
                                        switch (lsDevice.deviceType) {
                                            case "iphone":
                                            case "ios":
                                            case "apple":
                                                return "apple";
                                            case "android":
                                            case "phone":
                                            case "mobile":
                                                return "smartphone";
                                            case "laptop":
                                            case "notebook":
                                                return "laptop";
                                            case "pc":
                                            case "desktop":
                                            default:
                                                return "monitor";
                                        } 
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: lsDevice.width - 8 * pill.s
                                    text: lsDevice.alias
                                    color: lsDevMouse.containsMouse ? PillTheme.cream : PillTheme.dim
                                    font.family: PillTheme.font
                                    font.pixelSize: 9.5 * pill.s
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.NoWrap
                                }
                            }

                            MouseArea {
                                id: lsDevMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: PillLocalsend.sendTo(lsDevice.ip)
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        id: rest
        anchors.fill: parent
        opacity: (pill.expanded || pill.mode === "game" || pill.mode === "toast" || pill.mode === "osd" || pill.mode === "localsend") ? 0 : Math.pow(pill.morphCloseness, 0.6)
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: pill.mode === "rest" ? PillMotion.fast : Math.round(0 * PillMotion.mult) } }

        Row {
            id: restRow
            anchors.centerIn: parent
            spacing: 9 * pill.s
            opacity: 1
            scale: 1

            Item {
                id: restKanji
                anchors.verticalCenter: parent.verticalCenter
                width: kanjiFill.implicitWidth
                height: kanjiFill.implicitHeight

                GlyphIcon {
                    anchors.centerIn: parent
                    opacity: 0
                    width: 0
                    height: 0
                    name: "clock"
                    color: PillTheme.cream
                    stroke: 1.7
                }
            }
        }
    }

    Item {
        id: hover
        anchors.fill: parent

        property bool delayPassed: false

        Timer {
            id: hoverDelayTimer
            interval: 300
            repeat: false
            running: pill.mode === "hover" && !pill.surfaceOpen
            onTriggered: hover.delayPassed = true
        }

        Connections {
            target: pill
            function onModeChanged() {
                if (pill.mode !== "hover" || pill.surfaceOpen) {
                    hover.delayPassed = false
                    hoverDelayTimer.stop()
                }
            }
        }

        opacity: (!pill.surfaceOpen && pill.mode === "hover" && delayPassed) ? 1 : 0
        visible: opacity > 0

        layer.enabled: pill.morphCloseness < 1.0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: (1.0 - pill.morphCloseness) * 1.0
        }

        Behavior on opacity {
            NumberAnimation { 
                duration: 50 
                easing.type: Easing.Bezier
                easing.bezierCurve: [0.165, 0.84, 0.44, 1, 1, 1]
            }
        }
        
        readonly property bool live: pill.mode === "hover" && delayPassed && !pill.surfaceOpen
        Row {
            id: hoverRow
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            spacing: Math.round((Config.options?.bar?.pill?.rowSpacing ?? 20) * pill.s)

            PillWorkspaces {
                id: ws
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth
                visible: pill.hoverModules?.workspaces ?? true
                screenName: pill.screenName
                s: pill.s
                gap: 8 * pill.s
                enabled: hover.live
                onHoverIndexChanged: if (hoverIndex >= 0) {
                    pill.soulTarget = "ws";
                    pill.soulWsIndex = hoverIndex;
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 22 * pill.s
                visible: ws.visible
                color: PillTheme.hair
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.ceil(hoverClock.implicitWidth)
                height: Math.ceil(hoverClock.implicitHeight)

                Column {
                    id: hoverClock
                    anchors.centerIn: parent
                    spacing: 2 * pill.s
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: clock.hhmm
                        color: PillTheme.cream
                        font.family: PillTheme.font
                        font.pixelSize: 18 * pill.s
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: clock.date
                        color: PillTheme.dim
                        font.family: PillTheme.font
                        font.pixelSize: 8.5 * pill.s
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.6 * pill.s
                    }
                }

                MouseArea {
                    anchors.centerIn: parent
                    width: hoverClock.implicitWidth + 22 * pill.s
                    height: hoverClock.implicitHeight + 10 * pill.s
                    enabled: hover.live
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pill.requestSurface("calendar")
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 22 * pill.s
                visible: statusRow.visibleChildren.length > 0
                color: PillTheme.hair
            }

            Row {
                id: statusRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round((Config.options?.bar?.pill?.iconSpacing ?? 12) * pill.s)

                Row {
                    id: weatherGlance
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (pill.hoverModules?.weather ?? true) && PillWeather.ready
                    spacing: 5 * pill.s

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                        enabled: hover.live
                    }
                    TapHandler {
                        enabled: hover.live
                        onTapped: pill.requestSurface("calendar")
                    }

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16 * pill.s
                        height: 16 * pill.s
                        name: PillWeather.glyphFor(PillWeather.codeNow, PillWeather.isDay)
                        color: PillTheme.subtle
                        stroke: 1.8
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: PillWeather.tempNow + "°"
                        color: PillTheme.subtle
                        font.family: PillTheme.font
                        font.pixelSize: 12.5 * pill.s
                        font.weight: Font.Medium
                        font.features: ({ "tnum": 1 })
                    }
                }

                Tray {
                    id: trayRowItem
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.hoverModules?.tray ?? true
                    s: pill.s
                    barWindow: pill.barWindow
                    enabled: hover.live
                    menuOpen: pill.trayMenuOpen
                    onMenuRequested: (item, anchorX) => pill.trayMenuRequested(item, anchorX)
                }

                Item {
                    id: wifiIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (pill.hoverModules?.wifi ?? true) && Network.wifiEnabled
                    width: pill.iconPx
                    height: pill.iconPx

                    WifiGlyph {
                        anchors.centerIn: parent
                        s: pill.s
                        level: Network.networkStrength / 100
                        on: Network.wifiEnabled
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pill.linkInitialView = "wifi";
                            pill.requestSurface("link");
                        }
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "wifi"
                    }
                }

                Item {
                    id: batteryIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (pill.hoverModules?.battery ?? true) && Battery.available
                    width: Math.ceil(battPct.implicitWidth)
                    height: pill.iconPx

                    Text {
                        id: battPct
                        anchors.centerIn: parent
                        text: Math.round(Battery.percentage * 100) + "%"
                        color: Battery.isLow ? PillTheme.vermLit
                            : (Battery.isCharging ? PillTheme.flameGlow : PillTheme.subtle)
                        font.family: PillTheme.font
                        font.pixelSize: 13 * pill.s
                        font.weight: Battery.isCharging ? Font.DemiBold : Font.Medium
                        font.features: ({ "tnum": 1 })
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("battery")
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "battery"
                    }
                }

                Item {
                    id: inboxIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.hoverModules?.inbox ?? true
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "inbox"
                        color: inboxArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.7
                    }

                    Rectangle {
                        visible: Notifications.unread > 0
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -2 * pill.s
                        anchors.rightMargin: -2 * pill.s
                        width: 5 * pill.s
                        height: 5 * pill.s
                        radius: width / 2
                        color: PillTheme.flameGlow
                    }

                    MouseArea {
                        id: inboxArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("link")
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "inbox"
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 18 * pill.s
                    color: PillTheme.hair
                    visible: (weatherGlance.visible || trayRowItem.visible || wifiIcon.visible || batteryIcon.visible || inboxIcon.visible)
                        && (launcherIcon.visible || glanceIcon.visible || mixerIcon.visible || clipboardIcon.visible || recorderIcon.visible || sysmonIcon.visible || localsendIcon.visible)
                }

                Item {
                    id: launcherIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.launcherEnabled
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "app-window"
                        color: launcherArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: launcherArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("launcher")
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "launcher"
                    }
                }

                Item {
                    id: glanceIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.glanceEnabled
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "agenda"
                        color: glanceArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: glanceArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("glance")
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "glance"
                    }
                }

                Item {
                    id: mixerIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.hoverModules?.mixer ?? true
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "mixer"
                        color: mixerArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: mixerArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("mixer")
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "mixer"
                    }
                }

                Item {
                    id: clipboardIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.clipboardEnabled
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "clipboard"
                        color: clipboardArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: clipboardArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("clipboard")
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "clipboard"
                    }
                }

                Item {
                    id: recorderIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.recorderEnabled
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "record"
                        color: RecorderStatus.isRecording ? PillTheme.vermLit
                            : (recorderArea.containsMouse ? PillTheme.cream : PillTheme.iconDim)
                        stroke: 1.7
                    }

                    MouseArea {
                        id: recorderArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("recorder")
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "recorder"
                    }
                }

                // --- BOUTON LOCALSEND (GLYPHE CARRÉ) ---
                Item {
                    id: localsendIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.localsendEnabled
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "square"
                        color: localsendArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: localsendArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            PillLocalsend.openManual()
                        }
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "localsend"
                    }
                }

                Item {
                    id: sysmonIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.sysmonEnabled
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "monitor"
                        color: sysmonArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: sysmonArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("sysmon")
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "sysmon"
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 18 * pill.s
                    color: PillTheme.hair
                    visible: (launcherIcon.visible || glanceIcon.visible || mixerIcon.visible || clipboardIcon.visible || recorderIcon.visible || sysmonIcon.visible || localsendIcon.visible
                        || weatherGlance.visible || trayRowItem.visible || wifiIcon.visible || batteryIcon.visible || inboxIcon.visible)
                        && (sidebarLeftIcon.visible || sidebarRightIcon.visible || powerIcon.visible)
                }

                Item {
                    id: sidebarLeftIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: false
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "sparkles"
                        color: sidebarLeftArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: sidebarLeftArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            GlobalStates.toggleSidebarLeft(pill.screenName);
                            pill.pinned = false;
                        }
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "sidebarLeft"
                    }
                }

                Item {
                    id: sidebarRightIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: false
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "cog"
                        color: sidebarRightArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.6
                    }

                    MouseArea {
                        id: sidebarRightArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            GlobalStates.toggleSidebarRight(pill.screenName);
                            pill.pinned = false;
                        }
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "sidebarRight"
                    }
                }

                Item {
                    id: powerIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.hoverModules?.power ?? true
                    width: pill.iconPx
                    height: pill.iconPx

                    GlyphIcon {
                        anchors.fill: parent
                        name: "shutdown"
                        color: powerArea.containsMouse ? PillTheme.cream : PillTheme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: powerArea
                        anchors.fill: parent
                        anchors.margins: -8 * pill.s
                        hoverEnabled: true
                        enabled: hover.live
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.requestSurface("power")
                        onContainsMouseChanged: if (containsMouse) pill.soulTarget = "power"
                    }
                }
            }
        }
    }

    PillOsd {
        id: osd
        anchors.fill: parent
        anchors.topMargin: (pill.compactAnnounceMode ? 7 : 12) * pill.s
        anchors.leftMargin: (pill.compactAnnounceMode ? 12 : 18) * pill.s
        anchors.rightMargin: (pill.compactAnnounceMode ? 12 : 18) * pill.s
        anchors.bottomMargin: (pill.compactAnnounceMode ? 7 : 12) * pill.s
        s: pill.s
        compact: pill.compactAnnounceMode
        screenName: pill.screenName
        outputAllowed: pill.osdOutputEnabled
        suppressed: pill.surfaceOpen || pill.held
        expanded: pill.expanded

        enabled: pill.mode === "osd"
        opacity: pill.mode === "osd" ? 1 : 0

        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: PillMotion.standard; easing.type: PillMotion.easeStandard }
        }
    }

    Loader {
        id: ldPower
        active: false
        anchors.fill: parent
        opacity: pill.surface === "power" ? 1 : 0
        visible: opacity > 0.01

        layer.enabled: opacity > 0 && opacity < 1
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: (1.0 - pill.morphCloseness) * 5.0
        }

        sourceComponent: PillPower {
            s: pill.s
            open: pill.surface === "power"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Loader {
        id: ldMedia
        active: false
        anchors.fill: parent
        opacity: pill.surface === "media" ? 1 : 0
        visible: opacity > 0.01
        sourceComponent: PillMedia {
            s: pill.s
            open: pill.surface === "media"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Loader {
        id: ldBattery
        active: false
        anchors.fill: parent
        opacity: pill.surface === "battery" ? 1 : 0
        visible: opacity > 0.01
        sourceComponent: PillBatterySurface {
            s: pill.s
            open: pill.surface === "battery"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Loader {
        id: ldCalendar
        active: false
        anchors.fill: parent
        opacity: pill.surface === "calendar" ? 1 : 0
        visible: opacity > 0.01
        sourceComponent: PillCalendar {
            s: pill.s
            open: pill.surface === "calendar"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Loader {
        id: ldLink
        active: false
        anchors.fill: parent
        opacity: pill.surface === "link" ? 1 : 0
        visible: opacity > 0.01
        sourceComponent: PillLink {
            s: pill.s
            open: pill.surface === "link"
            initialView: pill.linkInitialView
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Loader {
        id: ldMixer
        active: false
        anchors.fill: parent
        opacity: pill.surface === "mixer" ? 1 : 0
        visible: opacity > 0.01
        sourceComponent: PillMixer {
            s: pill.s
            open: pill.surface === "mixer"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Loader {
        id: ldSysmon
        active: false
        anchors.fill: parent
        opacity: pill.surface === "sysmon" ? 1 : 0
        visible: opacity > 0.01
        sourceComponent: PillSysmonSurface {
            s: pill.s
            open: pill.surface === "sysmon"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Loader {
        id: ldClipboard
        active: false
        anchors.fill: parent
        opacity: pill.surface === "clipboard" ? 1 : 0
        visible: opacity > 0.01
        sourceComponent: PillClipboard {
            s: pill.s
            open: pill.surface === "clipboard"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Loader {
        id: ldGlance
        active: false
        anchors.fill: parent
        opacity: pill.surface === "glance" ? 1 : 0
        visible: opacity > 0.01
        sourceComponent: PillGlance {
            s: pill.s
            open: pill.surface === "glance"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestJump: (name) => pill.requestSurface(name)
        }
    }

    Loader {
        id: ldLauncher
        active: false
        anchors.fill: parent
        opacity: pill.surface === "launcher" ? 1 : 0
        visible: opacity > 0.01
        sourceComponent: PillLauncher {
            s: pill.s
            open: pill.surface === "launcher"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    }

    Loader {
        id: ldRecorder
        active: false
        anchors.fill: parent
        sourceComponent: PillRecorder {
            s: pill.s
            open: pill.surface === "recorder"
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
        }
    } 

    Loader {
        id: toastLoader
        active: pill.toastActive
        anchors.fill: parent
        anchors.topMargin: (pill.compactAnnounceMode ? 6 : 12) * pill.s
        anchors.leftMargin: (pill.compactAnnounceMode ? 8 : 16) * pill.s
        anchors.rightMargin: (pill.compactAnnounceMode ? 8 : 16) * pill.s
        anchors.bottomMargin: (pill.compactAnnounceMode ? 6 : 12) * pill.s
        enabled: pill.mode === "toast"
        opacity: pill.mode === "toast" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: PillMotion.standard; easing.type: PillMotion.easeStandard } }

        sourceComponent: Toast {
            s: pill.s
            compact: pill.compactAnnounceMode
            live: pill.mode === "toast"
            notif: PillNotifs.popups[PillNotifs.popups.length - 1]
        }
    }
}