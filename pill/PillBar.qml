pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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

    // ghostBind = activé par le bind Hyprland via IPC
    // isHoveringAnyPill = vrai tant que le curseur (position GLOBALE via `hyprctl cursorpos`)
    //   est au-dessus de la zone de la pill sur un des écrans.
    //   On NE PEUT PAS utiliser un HoverHandler classique ici : dès que ghostMode passe
    //   à true on retire la pill du mask (input region) pour laisser passer les clics
    //   vers les fenêtres en dessous, donc notre surface ne reçoit plus AUCUN évènement
    //   souris sur cette zone (ni hover, ni clic) -> un HoverHandler y perdrait le survol
    //   instantanément, ce qui recréerait la boucle infinie décrite plus bas.
    //   La détection se fait donc en dehors du système d'input Wayland de cette fenêtre,
    //   via un polling de `hyprctl cursorpos` (voir ghostHoverPoll dans chaque overlay),
    //   ce qui reste fiable même quand le mask exclut totalement la pill.
    // ghostMode = les deux réunis (bind tenu + curseur au-dessus de la pill)
    property bool ghostBind: false
    property var pillHoverByScreen: ({})
    readonly property bool isHoveringAnyPill: Object.values(root.pillHoverByScreen).some(v => v === true)
    readonly property bool ghostMode: ghostBind && isHoveringAnyPill

    // ghostEpoch : incrémenté à CHAQUE changement de ghostBind. Sert à identifier/rejeter
    // les réponses `hyprctl cursorpos` encore "en vol" au moment où le bind est relâché.
    // Sans ça, une réponse asynchrone en retard pouvait réécrire pillHoverByScreen à `true`
    // juste APRÈS que le relâchement du bind l'ait remis à `false`, laissant un état
    // "coincé" qui perturbait tout le comportement de hover ensuite.
    property int ghostEpoch: 0
    onGhostBindChanged: root.ghostEpoch++

    function setPillHovered(screenName: string, hovered: bool): void {
        if (!screenName || root.pillHoverByScreen[screenName] === hovered)
            return
        const next = Object.assign({}, root.pillHoverByScreen)
        next[screenName] = hovered
        root.pillHoverByScreen = next
    }

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
        // ghostBind activé/désactivé via IPC ; ghostMode ne devient vrai que si la souris est aussi sur la pill
        function setGhostMode(state: bool): void {
            root.ghostBind = state;
        }
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
            readonly property string screenName: modelData ? modelData.name : ""
            readonly property real screenGlobalX: modelData ? modelData.x : 0
            readonly property real screenGlobalY: modelData ? modelData.y : 0
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

            // === RESYNC APRÈS SORTIE DU GHOST MODE ===
            // Pendant mask = emptyOverlay, aucun évènement Wayland n'atteint cette fenêtre,
            // donc pill.hovered / pointerReveal restent figés sur leur dernière valeur réelle
            // (typiquement `true`, puisque la souris était sur la pill quand le ghost s'est
            // activé). Si on repasse en interactiveRegion pendant que le curseur réel est
            // maintenant EN DEHORS de la pill (sortie détectée par le poll, ou bind relâché
            // avec le curseur ailleurs), aucun évènement "leave" Wayland ne viendra jamais
            // corriger cet état : il resterait bloqué "hovered" indéfiniment, ce qui provoque
            // exactement le symptôme observé (pill qui réapparaît "cassée", puis un simple
            // survol plus tard qui semble faire apparaître/disparaître la pill tout seul).
            // On force donc un reset ici ; si le curseur est réellement encore dessus, un
            // nouvel évènement d'entrée Wayland le remettra à jour tout de suite après.
            function forceHoverResync(): void {
                pointerHideGrace.stop()
                pointerReveal = false
                pill.hovered = false
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

            onAutoHideHiddenChanged: {
                console.log("[pill-dnd]", screenName, "autoHideHidden ->", autoHideHidden);
                root.setAutoHideShown(modelData?.name ?? "", !autoHideHidden);
            }
            Component.onCompleted: {
                console.log("[pill-dnd]", screenName, "overlay ready, screenGlobalX/Y =",
                    screenGlobalX, screenGlobalY, "autoHideEnabled =", autoHideEnabled);
                root.setAutoHideShown(modelData?.name ?? "", !autoHideHidden);
            }

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

            // Quand le ghost mode est actif (bind tenu + curseur sur la pill) et qu'aucune
            // surface n'est ouverte, on vide complètement le mask : la fenêtre ne reçoit
            // plus aucun évènement souris et les clics tombent directement sur ce qu'il y a
            // en dessous (apps, bureau...). Le survol pendant cette période est détecté à
            // côté, par polling (voir ghostHoverPoll plus bas), donc pas de boucle de
            // rétroaction possible.
            mask: (root.ghostMode && !modal)
                ? emptyOverlay
                : (modal ? fullRegion : (pill.fsHide ? emptyOverlay : interactiveRegion))
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
                id: mediaSubRegion
                readonly property point mapped: {
                    mediaSub.visible; mediaSub.x; mediaSub.y; mediaSub.width; mediaSub.height;
                    islandContainer.x; islandContainer.y; islandContainer.width;
                    return mediaSub.visible ? mediaSub.mapToItem(spectrumScope, 0, 0) : Qt.point(-9999, -9999);
                }
                x: mapped.x; y: mapped.y
                width: mediaSub.visible ? mediaSub.width : 0
                height: mediaSub.visible ? mediaSub.height : 0
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
                Region { item: mediaSub }
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

                // Pendant un drag-and-drop externe (fichier tiré depuis un file manager),
                // le compositeur bascule sur wl_data_device et n'envoie plus les évènements
                // wl_pointer normaux -> edgeRevealHover ne se déclenche JAMAIS pendant un
                // drag, donc pointerReveal reste false et la pill reste hors-écran (voir
                // anchors.topMargin plus bas). Ce DropArea capte spécifiquement le DnD pour
                // forcer le reveal, indépendamment du hover souris classique.
                DropArea {
                    id: edgeRevealDrop
                    anchors.fill: parent
                    onEntered: (drag) => {
                        console.log("[pill-dnd]", overlay.screenName, "edgeRevealDrop ENTERED hasUrls =", drag.hasUrls,
                            "autoHideHidden =", overlay.autoHideHidden);
                        if (drag.hasUrls) {
                            pointerHideGrace.stop();
                            overlay.pointerReveal = true;
                            islandContainer.lsDragActive = true;
                        }
                    }
                    onExited: {
                        console.log("[pill-dnd]", overlay.screenName, "edgeRevealDrop EXITED");
                        overlay.syncPointerReveal();
                    }
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

            // === DÉTECTION DU GHOST MODE PAR POLLING (hors input region Wayland) ===
            // On interroge périodiquement `hyprctl cursorpos` (position GLOBALE du curseur,
            // en pixels "layout" Hyprland) et on la compare aux bornes globales de la zone
            // interactive de CET écran. Ça fonctionne même quand le mask est vide (clic-through
            // actif), puisque ça ne dépend pas des évènements souris reçus par la fenêtre.
            // Le polling ne tourne que pendant que ghostBind est actif (coût nul sinon).
            Process {
                id: ghostCursorProc
                command: ["hyprctl", "cursorpos"]
                // Epoch capturé au moment du lancement de CETTE requête. Si ghostBind change
                // (et donc root.ghostEpoch s'incrémente) avant que la réponse n'arrive, on sait
                // que ce résultat est obsolète et on l'ignore : ça évite qu'une réponse en
                // retard écrase l'état juste remis à jour par le relâchement du bind.
                property int requestEpoch: 0
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (ghostCursorProc.requestEpoch !== root.ghostEpoch)
                            return

                        const wasHovering = root.pillHoverByScreen[overlay.screenName] === true
                        const m = text.match(/(-?\d+)\s*,\s*(-?\d+)/)
                        let inside = false
                        if (m) {
                            const gx = parseInt(m[1])
                            const gy = parseInt(m[2])
                            const left = overlay.screenGlobalX + interactiveRegion.x
                            const top = overlay.screenGlobalY + interactiveRegion.y
                            inside = gx >= left && gx <= left + interactiveRegion.width
                                && gy >= top && gy <= top + interactiveRegion.height
                        }

                        root.setPillHovered(overlay.screenName, inside)

                        // Transition "on était en ghost sur la pill" -> "on ne l'est plus" :
                        // le mask va repasser en interactiveRegion alors que le curseur réel
                        // est déjà dehors -> aucun évènement Wayland ne viendra nettoyer
                        // pill.hovered tout seul, donc on le fait explicitement ici.
                        if (wasHovering && !inside)
                            overlay.forceHoverResync()
                    }
                }
            }

            Timer {
                id: ghostHoverPoll
                interval: 90
                repeat: true
                running: root.ghostBind
                onTriggered: {
                    if (!ghostCursorProc.running) {
                        ghostCursorProc.requestEpoch = root.ghostEpoch
                        ghostCursorProc.running = true
                    }
                }
            }

            Connections {
                target: root
                function onGhostBindChanged(): void {
                    if (root.ghostBind)
                        return
                    // Bind relâché : on tue toute requête hyprctl encore en vol (son résultat
                    // serait de toute façon ignoré via l'epoch, mais autant ne pas la laisser
                    // traîner) et on force le resync si on était en train de "ghost-hover".
                    ghostCursorProc.running = false
                    const wasHovering = root.pillHoverByScreen[overlay.screenName] === true
                    root.setPillHovered(overlay.screenName, false)
                    if (wasHovering)
                        overlay.forceHoverResync()
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
                        if (mediaSubHover.hovered || recordSubHover.hovered)
                            return
                        // On met à jour pill.hovered pour le suivi (autoHide, ghost, etc.)
                        // mais on NE déclenche PAS l'expand visuel (géré par le clic uniquement)
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

                    opacity: root.ghostMode ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
                    }

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
                    // true tant qu'un fichier est en train d'être survolé au-dessus de la
                    // pill (avant même le drop) -- fait grossir la pill elle-même (mode
                    // "localsend" dans Pill.qml) pour prévisualiser la zone de dépôt.
                    property bool lsDragActive: false
                    readonly property real rightOutWidth: {
                        if (mediaSub.isOut) return mediaSub.width + subGap;
                        if (recordSub.isOut && !recordSub.goesLeft) return recordSub.width + subGap;
                        return 0;
                    }
                    readonly property real leftOutWidth: (recordSub.isOut && recordSub.goesLeft) ? (recordSub.width + subGap) : 0
                    readonly property real blockShift: (rightOutWidth - leftOutWidth) / 2

                    anchors.horizontalCenterOffset: -blockShift

                    Behavior on anchors.horizontalCenterOffset {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }

                    width: pill.width
                    height: pill.height

                    Behavior on anchors.topMargin {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    // === ZONE DE DEPOT LOCALSEND ===
                    // Recouvre exactement la pill (même géométrie que pillRegion, donc déjà
                    // couverte par le mask). Ne consomme pas les clics/hover normaux : DropArea
                    // ne réagit qu'aux évènements de drag&drop, jamais aux MouseArea/HoverHandler
                    // de la pill en dessous. Se contente de faire remonter l'état de survol/drop
                    // à islandContainer.lsDragActive puis à PillLocalsend : c'est la pill
                    // elle-même (voir Pill.qml, mode "localsend") qui s'agrandit pour l'accueillir,
                    // il n'y a plus de second îlot séparé ici.
                    DropArea {
                        id: lsDropArea
                        z: 3
                        anchors.fill: parent
                        onEntered: (drag) => {
                            console.log("[pill-dnd]", overlay.screenName, "lsDropArea ENTERED hasUrls =", drag.hasUrls);
                            if (drag.hasUrls) islandContainer.lsDragActive = true;
                        }
                        onExited: {
                            console.log("[pill-dnd]", overlay.screenName, "lsDropArea EXITED");
                            islandContainer.lsDragActive = false;
                        }
                        onPositionChanged: (drag) => {
                            console.log("[pill-dnd]", overlay.screenName, "lsDropArea MOVE", drag.x, drag.y);
                        }
                        onDropped: (drop) => {
                            console.log("[pill-dnd]", overlay.screenName, "lsDropArea DROPPED hasUrls =", drop.hasUrls, "urls =", drop.urls);
                            islandContainer.lsDragActive = false;
                            if (!drop.hasUrls) return;
                            const raw = drop.urls[0].toString().trim();
                            const path = raw.startsWith("file://") ? decodeURIComponent(raw.substring(7)) : raw;
                            console.log("[pill-dnd]", overlay.screenName, "resolved path =", path,
                                "typeof PillLocalsend.openSendPicker =", typeof PillLocalsend.openSendPicker);
                            if (typeof PillLocalsend.openSendPicker !== "function") {
                                console.warn("[pill-dnd]", overlay.screenName,
                                    "PillLocalsend.openSendPicker n'est pas une fonction ! PillLocalsend =", PillLocalsend,
                                    "keys =", Object.keys(PillLocalsend ?? {}));
                                drop.accept();
                                return;
                            }
                            PillLocalsend.openSendPicker(path);
                            drop.accept();
                        }
                    }

                    // --- 1. PILULE PRINCIPALE (z: 2) ---
                    Pill {
                        id: pill
                        z: 2
                        anchors.centerIn: parent
                        s: overlay.s
                        // L'expand est supprimé en permanence sur simple hover ;
                        // seul un clic (via isHoveredOrActive basé sur held/surfaceOpen) le déclenche.
                        suppressHoverExpand: true
                        screenName: overlay.modelData ? overlay.modelData.name : ""
                        barWindow: overlay
                        surface: overlay.surface
                        lsDragActive: islandContainer.lsDragActive

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

                        // L'expand ne se fait que sur clic (held) ou surface ouverte, PAS sur hover
                        readonly property bool isHoveredOrActive: (overlay.surfaceOpen || held)
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
                        id: mediaSub
                        z: 1
                        property bool forceRetract: false
                        readonly property bool pillIsCompact: pill.mode === "rest" && !pill.isHoveredOrActive
                        readonly property bool shouldShow: subManager.displayMedia && !pill.surfaceOpen
                        property bool delayedCompact: pillIsCompact

                        Timer {
                            id: mediaExitDelayTimer
                            interval: 500
                            repeat: false
                            onTriggered: mediaSub.delayedCompact = true
                        }

                        onPillIsCompactChanged: {
                            if (pillIsCompact) mediaExitDelayTimer.restart()
                            else { mediaExitDelayTimer.stop(); delayedCompact = false }
                        }

                        readonly property bool isOut: shouldShow && delayedCompact && !forceRetract
                        property bool visibleOpacity: true
                        property bool instantHideNext: false

                        onIsOutChanged: {
                            if (isOut) { mediaFadeOutTimer.stop(); visibleOpacity = true }
                            else { mediaFadeOutTimer.restart() }
                        }

                        onShouldShowChanged: {
                            if (!shouldShow) {
                                mediaFadeOutTimer.stop()
                                if (pill.surfaceOpen) { instantHideNext = true; visibleOpacity = false }
                                else visibleOpacity = false
                            }
                        }

                        Timer {
                            id: mediaFadeOutTimer
                            interval: 300
                            repeat: false
                            onTriggered: mediaSub.visibleOpacity = false
                        }

                        width: pill.height; height: pill.height; radius: width / 2
                        color: "#000000"; border.width: shouldShow ? 1 : 0; border.color: "#333333"
                        clip: true

                        x: isOut ? (pill.targetW + islandContainer.subGap) : (parent.width / 2 - width / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: (shouldShow && visibleOpacity) ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        Behavior on opacity { enabled: !mediaSub.instantHideNext; NumberAnimation { duration: 200 } }
                        onOpacityChanged: { if (instantHideNext) instantHideNext = false }

                        HoverHandler { id: mediaSubHover }

                        MouseArea {
                            anchors.fill: parent
                            enabled: mediaSub.isOut
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof pill !== "undefined" && pill.requestSurface) {
                                    mediaSub.forceRetract = true;
                                    mediaOpenDelay.restart();
                                }
                            }
                        }

                        Timer {
                            id: mediaOpenDelay
                            interval: 320
                            repeat: false
                            onTriggered: { pill.requestSurface("media"); mediaSub.forceRetract = false; }
                        }

                        Image {
                            id: innerCoverImg
                            anchors.centerIn: parent
                            width: parent.height * 0.55; height: parent.height * 0.55
                            source: PillPlayers.artUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: false
                        }

                        OpacityMask {
                            anchors.fill: innerCoverImg
                            source: innerCoverImg
                            maskSource: Rectangle { width: innerCoverImg.width; height: innerCoverImg.height; radius: 20 }
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
                            if (pillIsCompact) recordExitDelayTimer.restart()
                            else { recordExitDelayTimer.stop(); delayedCompact = false }
                        }

                        readonly property bool isOut: shouldShow && delayedCompact && !forceRetract
                        property bool visibleOpacity: true
                        property bool instantHideNext: false

                        onIsOutChanged: {
                            if (isOut) { recordFadeOutTimer.stop(); visibleOpacity = true }
                            else recordFadeOutTimer.restart()
                        }

                        onShouldShowChanged: {
                            if (!shouldShow) {
                                recordFadeOutTimer.stop()
                                if (pill.surfaceOpen) { instantHideNext = true; visibleOpacity = false }
                                else visibleOpacity = false
                            }
                        }

                        Timer {
                            id: recordFadeOutTimer
                            interval: 300
                            repeat: false
                            onTriggered: recordSub.visibleOpacity = false
                        }

                        width: pill.height; height: pill.height; radius: width / 2
                        color: "#000000"; border.width: shouldShow ? 1 : 0; border.color: "#333333"
                        clip: true

                        readonly property bool goesLeft: subManager.displayCount === 2
                        x: isOut
                            ? (goesLeft ? -(width + islandContainer.subGap) : (pill.targetW + islandContainer.subGap))
                            : (parent.width / 2 - width / 2)

                        anchors.verticalCenter: parent.verticalCenter
                        opacity: (shouldShow && visibleOpacity) ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        Behavior on opacity { enabled: !recordSub.instantHideNext; NumberAnimation { duration: 200 } }
                        onOpacityChanged: { if (instantHideNext) instantHideNext = false }

                        HoverHandler { id: recordSubHover }

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
                            onTriggered: { pill.requestSurface("recorder"); recordSub.forceRetract = false; }
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