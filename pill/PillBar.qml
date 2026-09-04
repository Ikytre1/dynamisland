pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Pill top shell.
 */
Scope {
    id: root
    property string openMon: ""
    property string openSurface: ""
    property bool openedViaIpc: false
    property var autoHideShownByScreen: ({})

    function setAutoHideShown(screenName: string, shown: bool): void {
        if (!screenName || root.autoHideShownByScreen[screenName] === shown)
            return
        const next = Object.assign({}, root.autoHideShownByScreen)
        next[screenName] = shown
        root.autoHideShownByScreen = next
    }

    function close() {
        openMon = "";
        openSurface = "";
        openedViaIpc = false;
        pill.hoverLatch = false;
        pill.hovered = false;
    }

    Connections {
        target: GlobalStates
        function onWidgetEditModeChanged(): void {
            if (GlobalStates.widgetEditMode)
                root.close()
        }
    }

    readonly property var surfaceNames: ["power", "media", "battery", "calendar", "link", "mixer", "sysmon", "clipboard", "glance", "launcher", "recorder"]
    readonly property var targetScreens: {
        const screens = Quickshell.screens;
        const list = Config.options?.bar?.screenList ?? [];
        if (!list || list.length === 0)
            return screens;
        const matchedScreens = screens.filter(screen => {
            const screenName = screen?.name ?? "";
            return screenName.length > 0 && list.includes(screenName);
        });
        return matchedScreens.length > 0 ? matchedScreens : screens;
    }

    function focusedScreenName() {
        const focused = CompositorService.isNiri ? NiriService.currentOutput : (Hyprland.focusedMonitor?.name ?? "");
        if (focused.length > 0 && root.targetScreens.some(screen => screen.name === focused))
            return focused;
        return root.targetScreens.length > 0 ? root.targetScreens[0].name : "";
    }

    function openSurfaceByName(surface) {
        if (!surfaceNames.includes(surface)) {
            console.warn(`[Pill] Unknown surface '${surface}'. Valid: ${surfaceNames.join(", ")}`);
            return;
        }
        openMon = focusedScreenName();
        openSurface = surface;
    }

    IpcHandler {
        target: "pill"

        function open(surface: string): void { 
            root.openedViaIpc = true;
            root.openSurfaceByName(surface); 
        }
        function close(): void { root.close() }
        function toggle(surface: string): void {
            if (root.openSurface === surface) {
                root.close();
            } else {
                root.openedViaIpc = true;
                root.openSurfaceByName(surface);
            }
        }
        function state(): string { return root.openSurface.length > 0 ? root.openSurface : "closed" }
    }
    
    readonly property real uiScale: Config.options?.bar?.pill?.scale ?? 1
    readonly property real topGap: Config.options?.bar?.pill?.topGap ?? 1
    readonly property real appGap: Config.options?.bar?.pill?.appGap ?? 1

    function openTrayMenu(item, anchorX, hostWindow) {
        trayMenu.s = hostWindow ? hostWindow.s : 1;
        trayMenu.hostWindow = hostWindow;
        trayMenu.open(item, anchorX);
    }

    PillTrayMenu {
        id: trayMenu
    }

    Variants {
        model: root.targetScreens

        PanelWindow {
            id: reserve
            required property var modelData

            readonly property real s: modelData ? (modelData.height / 1080) * root.uiScale : 1
            readonly property string screenName: modelData ? modelData.name : ""

            screen: modelData
            visible: !GlobalStates.widgetEditMode
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            aboveWindows: true

            anchors { top: true; left: true; right: true }
            implicitHeight: 0

            mask: emptyReserve
            Region { id: emptyReserve }
        }
    }

    Variants {
        model: root.targetScreens

        PanelWindow {
            id: overlay
            required property var modelData

            readonly property real s: modelData ? (modelData.height / 1080) * root.uiScale : 1
            readonly property real topGapPx: 8 * root.topGap * s
            readonly property string surface: root.openMon === modelData.name ? root.openSurface : ""
            readonly property bool surfaceOpen: surface.length > 0
            readonly property bool modal: surfaceOpen || pill.held
            readonly property bool autoHideEnabled: (Config.options?.bar?.autoHide?.enable ?? false)
                && !pill.fsHide
            readonly property bool transientMode: pill.mode !== "rest" && pill.mode !== "hover"
            property bool pointerReveal: false
            readonly property bool mustShow: !autoHideEnabled || pointerReveal
                || superShow || surfaceOpen || pill.held || pill.hoverLatch || transientMode
            readonly property bool autoHideHidden: autoHideEnabled && !mustShow
            property bool superShow: false

            function syncPointerReveal(): void {
                if (edgeRevealHover.hovered || pill.hovered) {
                    pointerHideGrace.stop()
                    pointerReveal = true
                } else if (pointerReveal) {
                    pointerHideGrace.restart()
                }
            }

            Timer {
                id: pointerHideGrace
                interval: 450
                repeat: false
                onTriggered: {
                    if (!edgeRevealHover.hovered && !pill.hovered)
                        overlay.pointerReveal = false
                }
            }

            Timer {
                id: showBarTimer
                interval: Config.options?.bar?.autoHide?.showWhenPressingSuper?.delay ?? 300
                repeat: false
                onTriggered: overlay.superShow = true
            }

            Connections {
                target: GlobalStates
                function onSuperDownChanged() {
                    if (!(Config.options?.bar?.autoHide?.showWhenPressingSuper?.enable ?? true))
                        return
                    if (GlobalStates.superDown)
                        showBarTimer.restart()
                    else {
                        showBarTimer.stop()
                        overlay.superShow = false
                    }
                }
            }

            onAutoHideHiddenChanged: root.setAutoHideShown(
                modelData?.name ?? "", !autoHideHidden)
            Component.onCompleted: root.setAutoHideShown(
                modelData?.name ?? "", !autoHideHidden)

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: surfaceOpen || pill.held
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "inir-pill"

            anchors { top: true; left: true; right: true; bottom: true }

            visible: !GlobalStates.widgetEditMode
                && (modal || !pill.fsHide || pill.opacity > 0.01)

            mask: modal ? fullRegion : (pill.fsHide ? emptyOverlay : interactiveRegion)
            Region { id: emptyOverlay }
            Region {
                id: pillRegion
                readonly property real baseW: Math.max(islandContainer.width, pill.targetW)
                x: islandContainer.x + (islandContainer.width - baseW) / 2
                y: islandContainer.y
                width: baseW + pill.inputPadRight
                height: Math.max(pill.height, pill.targetH)
            }
            Region {
                id: subPillRegion
                readonly property point mapped: {
                    subPill.visible;
                    subPill.x; subPill.y; subPill.width; subPill.height;
                    islandContainer.x; islandContainer.y; islandContainer.width;
                    return subPill.visible ? subPill.mapToItem(spectrumScope, 0, 0) : Qt.point(-9999, -9999);
                }
                x: mapped.x
                y: mapped.y
                width: subPill.visible ? subPill.width : 0
                height: subPill.visible ? subPill.height : 0
            }
            Region {
                id: recordSubRegion
                readonly property point mapped: {
                    recordSub.visible; recordSub.x; recordSub.y; recordSub.width; recordSub.height;
                    islandContainer.x; islandContainer.y; islandContainer.width;
                    return recordSub.visible ? recordSub.mapToItem(spectrumScope, 0, 0) : Qt.point(-9999, -9999);
                }
                x: mapped.x; y: mapped.y
                width: recordSub.visible ? recordSub.width : 0
                height: recordSub.visible ? recordSub.height : 0
            }
            Region {
                id: interactiveRegion
                x: pillRegion.x - islandContainer.leftOutWidth
                y: pillRegion.y
                width: pillRegion.width + islandContainer.leftOutWidth + islandContainer.rightOutWidth
                height: pillRegion.height
                Region { item: edgeRevealRegion }
                Region { item: subPill }
                Region { item: recordSub }
            }
            Region {
                id: fullRegion
                width: overlay.width
                height: overlay.height
            }

            Item {
                id: edgeRevealRegion
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: overlay.autoHideEnabled
                    ? Math.max(1, Config.options?.bar?.autoHide?.hoverRegionWidth ?? 2) : 0
                HoverHandler {
                    id: edgeRevealHover
                    onHoveredChanged: overlay.syncPointerReveal()
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: overlay.modal
                acceptedButtons: Qt.AllButtons
                onPressed: (mouse) => {
                    if (overlay.surfaceOpen) {
                        const inside = mouse.x >= pillRegion.x && mouse.x <= pillRegion.x + pillRegion.width
                            && mouse.y >= pillRegion.y && mouse.y <= pillRegion.y + pillRegion.height;
                        if (!inside)
                            root.close();
                    } else {
                        pill.pinned = false;
                    }
                }
            }

            FocusScope {
                id: spectrumScope
                anchors.fill: parent
                focus: overlay.surfaceOpen

                readonly property bool spectrumPlaying: PillPlayers.playing || YtMusic.isPlaying
                readonly property bool spectrumOutputEnabled:
                    (Config.options?.bar?.visualizer?.multiMonitorMode ?? "primary") === "all"
                    || Quickshell.screens.length <= 1
                    || String(overlay.modelData?.name ?? "")
                        === String(GlobalStates.primaryScreen?.name ?? "")
                readonly property bool spectrumConfigured: (Config.options?.bar?.pill?.musicViz ?? true)
                    && spectrumOutputEnabled
                    && !Appearance.gameModeMinimal
                readonly property bool spectrumProcessWanted: spectrumConfigured && spectrumPlaying
                readonly property bool spectrumVisible: spectrumConfigured
                    && pillCava.audioSignalActive
                    && !pill.fsHide
                    && !overlay.surfaceOpen

                HoverHandler {
                    id: globalHover
                    onHoveredChanged: {
                        if (subPillHover.hovered || recordSubHover.hovered)
                            return
                        pill.hovered = hovered
                        overlay.syncPointerReveal()
                    }
                }
                Keys.onEscapePressed: {
                    root.close();
                }

                CavaProcess {
                    id: pillCava
                    active: spectrumScope.spectrumProcessWanted
                    sampleCount: pillWings.requestedSampleCount
                }

                PillSpectrumWings {
                    id: pillWings
                    anchors.fill: parent
                    pillItem: pill
                    active: spectrumScope.spectrumVisible
                    points: active ? pillCava.points : []
                    normalizationCeiling: active ? pillCava.normalizationCeiling : 100
                    s: overlay.s
                }

                Item {
                    id: islandContainer
                    anchors.top: parent.top
                    anchors.topMargin: pill.mode === "game" ? 0
                        : overlay.autoHideHidden
                            ? -(pill.hoverH + overlay.topGapPx + 1)
                            : (overlay.topGapPx + ((pill.isUp && (!PillPlayers.has || pill.hoverLatch)) ? 0 : (4 * s)))
                    anchors.horizontalCenter: parent.horizontalCenter

                    // === GESTIONNAIRE D'ETAT DES SOUS-ILOTS ===
                    Item {
                        id: subManager
                        readonly property bool rawMedia: PillPlayers.has
                        readonly property bool rawRecord: RecorderStatus.recorderPid > 0
                        readonly property int rawCount: (rawMedia ? 1 : 0) + (rawRecord ? 1 : 0)

                        property bool displayMedia: rawMedia
                        property bool displayRecord: rawRecord
                        property int displayCount: rawCount
                        property bool inSwap: false

                        onRawCountChanged: {
                            if (rawCount !== displayCount) {
                                if (rawCount > 0 && displayCount > 0) {
                                    inSwap = true;
                                    displayMedia = false;
                                    displayRecord = false;
                                    swapTimer.restart();
                                } else {
                                    displayCount = rawCount;
                                    displayMedia = rawMedia;
                                    displayRecord = rawRecord;
                                }
                            }
                        }

                        onRawMediaChanged: {
                            if (!inSwap && rawCount === displayCount) displayMedia = rawMedia;
                        }

                        onRawRecordChanged: {
                            if (!inSwap && rawCount === displayCount) displayRecord = rawRecord;
                        }

                        Timer {
                            id: swapTimer
                            interval: 320
                            onTriggered: {
                                subManager.displayCount = subManager.rawCount;
                                subManager.displayMedia = subManager.rawMedia;
                                subManager.displayRecord = subManager.rawRecord;
                                subManager.inSwap = false;
                            }
                        }
                    }

                    readonly property real subGap: 8 * s
                    readonly property real rightOutWidth: {
                        if (subPill.isOut) return subPill.width + subGap;
                        if (recordSub.isOut && !recordSub.goesLeft) return recordSub.width + subGap;
                        return 0;
                    }
                    readonly property real leftOutWidth: (recordSub.isOut && recordSub.goesLeft) ? (recordSub.width + subGap) : 0
                    readonly property real blockShift: (rightOutWidth - leftOutWidth) / 2

                    anchors.horizontalCenterOffset: -blockShift

                    Behavior on anchors.horizontalCenterOffset {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }

                    width: pill.width
                    height: pill.height

                    Behavior on anchors.topMargin {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                    }

                    // --- 1. PILULE PRINCIPALE (z: 2) ---
                    Pill {
                        id: pill
                        z: 2
                        anchors.centerIn: parent
                        s: overlay.s
                        suppressHoverExpand: requireMouseExit
                        screenName: overlay.modelData ? overlay.modelData.name : ""
                        barWindow: overlay
                        surface: overlay.surface

                        property bool requireMouseExit: false

                        onSurfaceChanged: {
                            if (surface === "") {
                                requireMouseExit = hovered
                            }
                        }

                        onHoveredChanged: {
                            if (!hovered) {
                                requireMouseExit = false
                            }
                        }

                        readonly property bool isHoveredOrActive: ((hovered && !requireMouseExit) || overlay.surfaceOpen || held)

                        property bool isUp: false
                        property bool allowExpand: false

                        Timer {
                            id: expandDelayTimer
                            interval: 280 
                            repeat: false
                            onTriggered: {
                                if (pill.isHoveredOrActive)
                                    pill.allowExpand = true
                            }
                        }

                        onIsHoveredOrActiveChanged: {
                            if (isHoveredOrActive) {
                                pill.isUp = true
                                expandDelayTimer.restart()
                            } else {
                                expandDelayTimer.stop()
                                pill.allowExpand = false
                            }
                        }

                        Connections {
                            target: pill
                            function onModeChanged() {
                                if (!pill.isHoveredOrActive && pill.mode === "rest") {
                                    pill.isUp = false
                                }
                            }
                        }

                        trayMenuOpen: trayMenu.shown

                        onRequestSurface: (name) => {
                            root.openMon = overlay.modelData.name;
                            root.openSurface = name;
                        }
                        onRequestClose: root.close()
                        onTrayMenuRequested: (item, anchorX) => root.openTrayMenu(item, anchorX, overlay)
                    }

                    // --- 2. SUBISLAND : MEDIA (z: 1) ---
                    Rectangle {
                        id: subPill
                        z: 1
                        property bool forceRetract: false

                        readonly property bool pillIsCompact: pill.mode === "rest" && !pill.isHoveredOrActive
                        readonly property bool shouldShow: subManager.displayMedia && !pill.surfaceOpen

                        property bool delayedCompact: pillIsCompact

                        Timer {
                            id: exitDelayTimer
                            interval: 500
                            repeat: false
                            onTriggered: subPill.delayedCompact = true
                        }

                        onPillIsCompactChanged: {
                            if (pillIsCompact) {
                                exitDelayTimer.restart()
                            } else {
                                exitDelayTimer.stop()
                                delayedCompact = false
                            }
                        }

                        readonly property bool isOut: shouldShow && delayedCompact && !forceRetract

                        property bool visibleOpacity: true
                        property bool instantHideNext: false

                        onIsOutChanged: {
                            if (isOut) {
                                fadeOutTimer.stop()
                                visibleOpacity = true
                            } else {
                                fadeOutTimer.restart()
                            }
                        }

                        onShouldShowChanged: {
                            if (!shouldShow) {
                                fadeOutTimer.stop()
                                if (pill.surfaceOpen) {
                                    instantHideNext = true
                                    visibleOpacity = false
                                } else {
                                    visibleOpacity = false
                                }
                            }
                        }

                        Timer {
                            id: fadeOutTimer
                            interval: 300
                            repeat: false
                            onTriggered: subPill.visibleOpacity = false
                        }

                        width: pill.height
                        height: pill.height
                        radius: width / 2

                        color: "#000000"
                        border.width: shouldShow ? 1 : 0
                        border.color: "#333333"
                        clip: true

                        x: isOut
                            ? (pill.targetW + islandContainer.subGap)
                            : (parent.width / 2 - width / 2)
                        anchors.verticalCenter: parent.verticalCenter

                        opacity: (shouldShow && visibleOpacity) ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on x {
                            NumberAnimation { 
                                duration: 300 
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on opacity {
                            enabled: !subPill.instantHideNext
                            NumberAnimation { duration: 200 }
                        }

                        onOpacityChanged: {
                            if (instantHideNext)
                                instantHideNext = false
                        }

                        HoverHandler {
                            id: subPillHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: subPill.isOut
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof pill !== "undefined" && pill.requestSurface) {
                                    subPill.forceRetract = true;
                                    mediaOpenDelay.restart();
                                }
                            }
                        }

                        Timer {
                            id: mediaOpenDelay
                            interval: 320
                            repeat: false
                            onTriggered: {
                                pill.requestSurface("media");
                                subPill.forceRetract = false;
                            }
                        }

                        Image {
                            id: innerCoverImg
                            anchors.centerIn: parent
                            width: parent.height * 0.55
                            height: parent.height * 0.55
                            source: PillPlayers.artUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: false
                        }

                        OpacityMask {
                            anchors.fill: innerCoverImg
                            source: innerCoverImg
                            maskSource: Rectangle {
                                width: innerCoverImg.width 
                                height: innerCoverImg.height
                                radius: 20
                            }
                        }
                    }

                    // --- 3. SUBISLAND : ENREGISTREMENT (z: 1) ---
                    Rectangle {
                        id: recordSub
                        z: 1
                        property bool forceRetract: false

                        readonly property bool pillIsCompact: pill.mode === "rest" && !pill.isHoveredOrActive
                        readonly property bool shouldShow: subManager.displayRecord && !pill.surfaceOpen

                        property bool delayedCompact: pillIsCompact

                        Timer {
                            id: recordExitDelayTimer
                            interval: 500
                            repeat: false
                            onTriggered: recordSub.delayedCompact = true
                        }

                        onPillIsCompactChanged: {
                            if (pillIsCompact) {
                                recordExitDelayTimer.restart()
                            } else {
                                recordExitDelayTimer.stop()
                                delayedCompact = false
                            }
                        }

                        readonly property bool isOut: shouldShow && delayedCompact && !forceRetract

                        property bool visibleOpacity: true
                        property bool instantHideNext: false

                        onIsOutChanged: {
                            if (isOut) {
                                recordFadeOutTimer.stop()
                                visibleOpacity = true
                            } else {
                                recordFadeOutTimer.restart()
                            }
                        }

                        onShouldShowChanged: {
                            if (!shouldShow) {
                                recordFadeOutTimer.stop()
                                if (pill.surfaceOpen) {
                                    instantHideNext = true
                                    visibleOpacity = false
                                } else {
                                    visibleOpacity = false
                                }
                            }
                        }

                        Timer {
                            id: recordFadeOutTimer
                            interval: 300
                            repeat: false
                            onTriggered: recordSub.visibleOpacity = false
                        }

                        width: pill.height
                        height: pill.height
                        radius: width / 2

                        color: "#000000"
                        border.width: shouldShow ? 1 : 0
                        border.color: "#333333"
                        clip: true

                        readonly property bool goesLeft: subManager.displayCount === 2
                        x: isOut
                            ? (goesLeft ? -(width + islandContainer.subGap) : (pill.targetW + islandContainer.subGap))
                            : (parent.width / 2 - width / 2)

                        anchors.verticalCenter: parent.verticalCenter

                        opacity: (shouldShow && visibleOpacity) ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on x {
                            NumberAnimation { 
                                duration: 300 
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on opacity {
                            enabled: !recordSub.instantHideNext
                            NumberAnimation { duration: 200 }
                        }

                        onOpacityChanged: {
                            if (instantHideNext)
                                instantHideNext = false
                        }

                        HoverHandler {
                            id: recordSubHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: recordSub.isOut
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof pill !== "undefined" && pill.requestSurface) {
                                    recordSub.forceRetract = true;
                                    recordOpenDelay.restart();
                                }
                            }
                        }

                        Timer {
                            id: recordOpenDelay
                            interval: 320
                            repeat: false
                            onTriggered: {
                                pill.requestSurface("recorder");
                                recordSub.forceRetract = false;
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.height * 0.35
                            height: parent.height * 0.35
                            radius: width / 2
                            color: "#ff4444"

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: recordSub.isOut
                                NumberAnimation { to: 0.3; duration: 800 }
                                NumberAnimation { to: 1.0; duration: 800 }
                            }
                        }
                    }
                }
            }
        }
    }
}