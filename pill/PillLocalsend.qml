pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LocalSend discovery/send/receive pour la pill.
 * State machine : "idle" -> "scanning" | "receiving" -> "ready" -> "sending" -> "idle"
 */
Singleton {
    id: root

    property bool manualMode: false
    property string lsSubMode: "choose" // "choose" | "send" | "receive"

    readonly property string scriptDir: Quickshell.env("HOME") + "/.config/quickshell/dynamisland/scripts/localsend"

    property string state: "idle" // idle | scanning | receiving | ready | sending
    property string pendingFile: ""
    readonly property string pendingFileName: pendingFile.length > 0 ? pendingFile.split("/").pop() : ""

    // Réception en temps réel
    property string recvSenderAlias: ""   // appareil qui envoie en ce moment
    property string recvState: "waiting"  // "waiting" | "transferring" | "done"
    property string recvLastFile: ""      // dernier fichier reçu (nom seul)
    property string recvCurrentFile: ""   // nom du fichier en cours de transfert
    property int recvProgress: 0          // 0-100, progression du transfert en cours

    ListModel { id: deviceModel }
    readonly property alias devices: deviceModel

    signal sendFinished(bool ok)
    signal receiveFinished(bool ok)

    function openManual() {
        manualMode = true;
        lsSubMode = "choose";
    }

    function setSubMode(mode) {
        lsSubMode = mode;
        if (mode === "receive") {
            startReceive();
        }
    }

function openSendPicker(file) {
    console.log("[PillLocalsend] openSendPicker appelé avec file =", file);
    if (!file)
        return;
    
    // Bascule immédiatement la sous-vue sur le mode "envoyer"
    lsSubMode = "send";
    
    pendingFile = file;
    deviceModel.clear();
    state = "scanning";
    
    console.log("[PillLocalsend] Lancement du script de découverte :", root.scriptDir + "/localsend_discover.sh");
    discoverProc.running = false;
    discoverProc.running = true;
}

    function startReceive() {
        console.log("[PillLocalsend] Démarrage du mode réception...");
        state = "receiving";
        recvSenderAlias = "";
        recvState = "waiting";
        recvLastFile = "";
        recvCurrentFile = "";
        recvProgress = 0;
        receiveProc.command = ["bash", scriptDir + "/localsend_receive.sh"];
        receiveProc.running = false;
        receiveProc.running = true;
    }

    function sendTo(ip) {
        console.log("[PillLocalsend] sendTo appelé vers IP =", ip, "avec pendingFile =", pendingFile);
        if (state !== "ready" || !pendingFile || !ip) {
            console.warn("[PillLocalsend] sendTo annulé : state =", state, "pendingFile =", pendingFile, "ip =", ip);
            return;
        }
        state = "sending";
        sendProc.command = ["bash", scriptDir + "/localsend_send.sh", pendingFile, ip];
        sendProc.running = true;
    }

    function cancel() {
        console.log("[PillLocalsend] Annulation demandée par l'utilisateur.");
        
        // 1. Stopper les bindings Quickshell
        discoverProc.running = false;
        sendProc.running = false;
        receiveProc.running = false;

        // 2. Force-kill instantané de tous les scripts et sous-processus Python LocalSend
        var killCmd = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        killCmd.command = ["pkill", "-9", "-f", "localsend"];
        killCmd.running = true;

        // 2b. Filet de sécurité : au cas où un process orphelin (dont le cmdline
        // ne contient pas "localsend") écouterait encore sur le port 53317,
        // on le tue directement par port. fuser en priorité, lsof en fallback.
        var killPort = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        killPort.command = ["bash", "-c",
            "fuser -k 53317/tcp 53317/udp 2>/dev/null; " +
            "lsof -ti:53317 2>/dev/null | xargs -r kill -9"];
        killPort.running = true;

        // 3. Réinitialiser les états UI et la machine à états
        state = "idle";
        manualMode = false;
        lsSubMode = "choose";
        pendingFile = "";
        deviceModel.clear();
    }

    Process {
        id: discoverProc
        command: ["bash", root.scriptDir + "/localsend_discover.sh"]
        stdout: StdioCollector { id: discoverOut }
        stderr: StdioCollector { id: discoverErr }
        
        onExited: (exitCode, exitStatus) => {
            console.log("[PillLocalsend] discoverProc terminé avec exitCode =", exitCode, "status =", exitStatus);
            console.log("[PillLocalsend] STDOUT brut reçu :\n" + discoverOut.text);
            if (discoverErr.text.trim().length > 0) {
                console.log("[PillLocalsend] STDERR brut reçu :\n" + discoverErr.text);
            }

            if (root.state !== "scanning") {
                console.warn("[PillLocalsend] Process terminé mais state n'était plus 'scanning' (state actuel =", root.state + ")");
                return;
            }

            deviceModel.clear();
            const rawText = discoverOut.text.trim();
            if (rawText.length === 0) {
                console.warn("[PillLocalsend] STDOUT est vide ! Aucun appareil détecté.");
            } else {
                const lines = rawText.split('\n');
                console.log("[PillLocalsend] Nombre de lignes à parser :", lines.length);
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (!line) continue;
                    
                    const parts = line.split('\t');
                    console.log("[PillLocalsend] Ligne", i, "parts =", JSON.stringify(parts));
                    
                    if (parts.length >= 2) {
                        const alias = parts[0].trim();
                        const ip = parts[1].trim();
                        const rawType = (parts.length >= 3) ? parts[2].trim().toLowerCase() : "desktop";

                        if (/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip)) {
                            deviceModel.append({ 
                                alias: alias, 
                                ip: ip,
                                deviceType: rawType 
                            });
                        }
                    }  
                }
            }

            console.log("[PillLocalsend] Nombre d'appareils dans deviceModel :", deviceModel.count);
            root.state = "ready";
            console.log("[PillLocalsend] Nouvel état :", root.state);
        }
    }

    Process {
        id: receiveProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                const trimmed = line.trim();
                if (trimmed.length === 0) return;
                console.log("[PillLocalsend] receive stdout:", trimmed);
                const parts = trimmed.split("\t");
                if (parts[0] === "RECEIVING" && parts.length >= 2) {
                    root.recvSenderAlias = parts[1];
                    root.recvState = "transferring";
                    root.recvLastFile = "";
                    root.recvCurrentFile = "";
                    root.recvProgress = 0;
                } else if (parts[0] === "PROGRESS" && parts.length >= 4) {
                    root.recvSenderAlias = parts[1];
                    root.recvCurrentFile = parts[2];
                    root.recvProgress = parseInt(parts[3], 10) || 0;
                    root.recvState = "transferring";
                } else if (parts[0] === "RECEIVED" && parts.length >= 3) {
                    root.recvSenderAlias = parts[1];
                    root.recvLastFile = parts[2];
                    root.recvProgress = 100;
                    root.recvState = "done";
                    // Repasse en "waiting" après 4s pour prêt à recevoir un autre
                    recvDoneTimer.restart();
                }
            }
        }
        stderr: StdioCollector { id: receiveErr }
        onExited: (exitCode) => {
            console.log("[PillLocalsend] receiveProc terminé avec exitCode =", exitCode);
            if (receiveErr.text) console.log("[PillLocalsend] Receive STDERR:", receiveErr.text);
            
            root.receiveFinished(exitCode === 0);
            if (root.state === "receiving") {
                root.state = "idle";
            }
        }
    }

    Timer {
        id: recvDoneTimer
        interval: 4000
        repeat: false
        onTriggered: {
            if (root.state === "receiving") {
                root.recvState = "waiting";
                root.recvSenderAlias = "";
                root.recvCurrentFile = "";
                root.recvProgress = 0;
            }
        }
    }

    Process {
        id: sendProc
        stdout: StdioCollector { id: sendOut }
        stderr: StdioCollector { id: sendErr }
        onExited: (exitCode) => {
            console.log("[PillLocalsend] sendProc terminé avec exitCode =", exitCode);
            if (sendOut.text) console.log("[PillLocalsend] Send STDOUT:", sendOut.text);
            if (sendErr.text) console.log("[PillLocalsend] Send STDERR:", sendErr.text);
            
            root.sendFinished(exitCode === 0);
            root.state = "idle";
            root.pendingFile = "";
        }
    }
}