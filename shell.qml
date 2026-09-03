//@ pragma UseQApplication
//@ pragma ShellId inir
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import qs.modules.common

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

import "./pill"
import "./modules/recordingOsd"

ShellRoot {
    id: root

    // Alias global requis par les sous-composants du dossier pill
    property alias pill: pillBarInstance

    Component.onCompleted: {
        Quickshell.watchFiles = true;

        FirstRunExperience.load();

        if (Config.ready) {
            Qt.callLater(() => ThemeService.applyCurrentTheme());
            Qt.callLater(() => IconThemeService.ensureInitialized());
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                Qt.callLater(() => ThemeService.applyCurrentTheme());
                Qt.callLater(() => IconThemeService.ensureInitialized());
            }
        }
    }

    // Instanciation directe du composant central PillBar
    PillBar {
        id: pillBarInstance
    }

    // Instanciation du module d'enregistrement d'écran


    // Système de toasts/notifications requis par la pill
    ToastManager {}
}