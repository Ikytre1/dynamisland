pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int revision: 0
    property bool isSettingsProcess: (Quickshell.env("INIR_STANDALONE_WINDOW") ?? "") === "1"
    property int readWriteDelay: 50
    property bool blockWrites: true
    property var customWidgetData: ({})
    property bool customWidgetDataSynced: false
    property var mascotInstances: ({})
    property bool mascotInstancesSynced: false

    signal configChanged

    function _bumpRevision(): void {
        root.revision = (root.revision + 1) % 2147483647;
    }

    function flushWrites(): void {}

    function _applyNestedKey(nestedKey, value) {
        let keys = Array.isArray(nestedKey) ? nestedKey : String(nestedKey).split(".");
        if (keys.length === 0) return;

        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try { convertedValue = JSON.parse(trimmed); } catch (e) {}
            }
        }

        let obj = root.options;
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") obj[keys[i]] = {};
            obj = obj[keys[i]];
        }
        obj[keys[keys.length - 1]] = convertedValue;
    }

    function setNestedValue(nestedKey, value) {
        _applyNestedKey(nestedKey, value);
        root._bumpRevision();
        root.configChanged();
    }

    function setNestedValues(updates) {
        if (!updates || typeof updates !== "object") return;
        const paths = Object.keys(updates);
        for (let i = 0; i < paths.length; ++i) {
            _applyNestedKey(paths[i], updates[paths[i]]);
        }
        if (paths.length > 0) {
            root._bumpRevision();
            root.configChanged();
        }
    }

    function addMascotInstance(initial): string {
        const id = Date.now().toString(36) + Math.floor(Math.random() * 1000).toString(36);
        const data = root._cloneObject(root.mascotInstances);
        data[id] = Object.assign({ enable: true }, initial ?? {});
        root.mascotInstances = data;
        root._bumpRevision();
        root.configChanged();
        return id;
    }

    function removeMascotInstance(id: string): void {
        if (!id || !root.mascotInstances || !(id in root.mascotInstances)) return;
        const data = root._cloneObject(root.mascotInstances);
        delete data[id];
        root.mascotInstances = data;
        root._bumpRevision();
        root.configChanged();
    }

    function getNestedValue(nestedKey, fallback) {
        let keys = Array.isArray(nestedKey) ? nestedKey : String(nestedKey).split(".");
        if (keys.length === 0) return fallback;

        root.revision;
        let obj = root.options;
        let startIndex = 0;

        if (keys.length >= 3 && keys[0] === "background" && keys[1] === "widgets" && keys[2] === "custom") {
            obj = root.customWidgetData;
            startIndex = 3;
        } else if (keys.length >= 3 && keys[0] === "background" && keys[1] === "widgets" && keys[2] === "mascotInstances") {
            obj = root.mascotInstances;
            startIndex = 3;
        }

        for (let i = startIndex; i < keys.length; ++i) {
            if (obj === undefined || obj === null) return fallback;
            obj = obj[keys[i]];
        }
        return (obj === undefined || obj === null) ? fallback : obj;
    }

    function _syncVarProperties(): void {
        let text = "";
        try { text = configFileView.text(); } catch (e) {}
        try {
            const raw = JSON.parse(text);
            root.customWidgetData = raw?.background?.widgets?.custom ?? {};
            root.customWidgetDataSynced = true;
            root.mascotInstances = raw?.background?.widgets?.mascotInstances ?? {};
            root.mascotInstancesSynced = true;
        } catch (e) {
            root.customWidgetDataSynced = false;
            root.mascotInstancesSynced = false;
        }
    }

    function _cloneObject(obj: var): var {
        try { return JSON.parse(JSON.stringify(obj ?? {})); } catch (e) { return {}; }
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: true
        onLoaded: {
            root._syncVarProperties();
            root._bumpRevision();
            root.ready = true;
        }
        onLoadFailed: error => {
            root.ready = true;
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property JsonObject bar: JsonObject {
                property string appearanceStyle: "pill"

                property JsonObject pill: JsonObject {
                    property bool barMode: false
                    property real scale: 1
                    property real opacity: 1
                    property real topGap: 1
                    property real appGap: 1
                    property bool showGlyphs: true
                    property bool clockSeconds: false
                    property bool time12h: false
                    property bool musicViz: true
                    property bool toasts: true
                    property bool osd: true
                    property bool compactAnnounces: false
                    property real rowSpacing: 20
                    property real iconSpacing: 12
                    property real iconSize: 17
                    property JsonObject soul: JsonObject {
                        property bool enable: true
                        property real size: 1
                        property string style: "orb"
                    }
                    property JsonObject glyphs: JsonObject {
                        property string clock: ""
                        property string media: ""
                        property string mediaPaused: ""
                        property string link: ""
                        property string notify: ""
                        property string clear: ""
                        property string dnd: ""
                        property string sysmon: ""
                        property string glance: ""
                        property string clipboard: ""
                        property string clipboardSearch: ""
                        property string recorder: ""
                        property string power: ""
                        property string battery: ""
                        property string calendar: ""
                        property string mixer: ""
                        property string launcher: ""
                        property string workspaces: ""
                    }
                    property JsonObject modules: JsonObject {
                        property bool workspaces: true
                        property bool weather: true
                        property bool tray: true
                        property bool wifi: true
                        property bool battery: true
                        property bool inbox: true
                        property bool mixer: true
                        property bool sidebars: true
                        property bool power: true
                    }
                    property JsonObject surfaces: JsonObject {
                        property bool sysmon: true
                        property bool clipboard: true
                        property bool glance: true
                        property bool launcher: true
                        property bool recorder: false
                    }
                }
            }
        }
    }
}