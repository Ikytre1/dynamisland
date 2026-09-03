#!/bin/bash
# LocalSend Receiver (Compatible iOS / Android / Desktop)
# Reçoit les fichiers envoyés via LocalSend et les enregistre dans ~/Téléchargements

SAVE_DIR="$HOME/Téléchargements"
[ ! -d "$SAVE_DIR" ] && SAVE_DIR="$HOME/Downloads"
mkdir -p "$SAVE_DIR"

notify-send "LocalSend Receiver" "Démarré et visible par iOS !" -i network-idle-symbolic

# On écrit le code dans un fichier temporaire dont le nom contient "localsend"
# (pour que pkill -f "localsend" puisse le matcher), puis on fait un exec :
# ça REMPLACE le process bash par python3 (même PID), au lieu d'en faire un
# enfant. Comme ça, tuer ce PID tue directement le serveur, plus d'orphelin
# qui continue à écouter sur le port 53317 après la fermeture de la pill.
TMP_SCRIPT=$(mktemp /tmp/localsend_receive_XXXXXX.py)
cleanup_tmp() { rm -f "$TMP_SCRIPT"; }
trap cleanup_tmp EXIT

cat > "$TMP_SCRIPT" <<EOF
import socket, json, ssl, threading, os, sys, uuid, hashlib, urllib.parse, urllib.request, re, subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from datetime import datetime, timedelta, timezone

MCAST_ADDR = '224.0.0.167'
PORT = 53317
SAVE_DIR = "$SAVE_DIR"
ALIAS = "QuickShell PC"

# ── 1. IP Réseau Local ───────────────────────────────────────────────
try:
    route_out = subprocess.check_output(["ip", "route", "get", MCAST_ADDR], text=True)
    src_m = re.search(r'src (\d+\.\d+\.\d+\.\d+)', route_out)
    LAN_IP = src_m.group(1) if src_m else '0.0.0.0'
except Exception:
    LAN_IP = '0.0.0.0'

# ── 2. Certificat TLS (Comportement identique à localsend_send.sh) ────
cache_dir = os.path.expanduser("~/.cache/qs_localsend_v2")
os.makedirs(cache_dir, exist_ok=True)
cert_file = os.path.join(cache_dir, "cert.pem")
key_file = os.path.join(cache_dir, "key.pem")

if not os.path.exists(cert_file) or not os.path.exists(key_file):
    from cryptography import x509
    from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    import ipaddress

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "LocalSend"),
        x509.NameAttribute(NameOID.COMMON_NAME, ALIAS)
    ])
    san = x509.SubjectAlternativeName([
        x509.DNSName("localhost"),
        x509.IPAddress(ipaddress.ip_address("127.0.0.1"))
    ])
    key_usage = x509.KeyUsage(
        digital_signature=True, key_encipherment=True, content_commitment=False,
        data_encipherment=False, key_agreement=False, key_cert_sign=False,
        crl_sign=False, encipher_only=False, decipher_only=False
    )
    ext_key_usage = x509.ExtendedKeyUsage([
        ExtendedKeyUsageOID.CLIENT_AUTH, ExtendedKeyUsageOID.SERVER_AUTH
    ])

    cert = x509.CertificateBuilder()\
        .subject_name(subject).issuer_name(issuer)\
        .public_key(key.public_key())\
        .serial_number(x509.random_serial_number())\
        .not_valid_before(datetime.now(timezone.utc) - timedelta(days=1))\
        .not_valid_after(datetime.now(timezone.utc) + timedelta(days=3650))\
        .add_extension(san, critical=False)\
        .add_extension(key_usage, critical=True)\
        .add_extension(ext_key_usage, critical=False)\
        .sign(key, hashes.SHA256())

    with open(key_file, "wb") as f:
        f.write(key.private_bytes(encoding=serialization.Encoding.PEM, format=serialization.PrivateFormat.TraditionalOpenSSL, encryption_algorithm=serialization.NoEncryption()))
    with open(cert_file, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))

with open(cert_file, "rb") as f:
    cert_pem_bytes = f.read()
    cert_der = ssl.PEM_cert_to_DER_cert(cert_pem_bytes.decode("utf-8"))
    FINGERPRINT = hashlib.sha256(cert_der).hexdigest().lower()

# Context SSL pour la réponse HTTP vers l'iPhone
ssl_ctx_client = ssl.create_default_context()
ssl_ctx_client.check_hostname = False
ssl_ctx_client.verify_mode = ssl.CERT_NONE

# ── 3. Écoute Multicast & Réponse HTTP /register vers iOS ────────────
def register_back_to_target(ip, port):
    """Envoie une notification POST /api/localsend/v2/register à l'iPhone"""
    payload = json.dumps({
        "alias": ALIAS,
        "version": "2.1",
        "deviceModel": "Linux",
        "deviceType": "desktop",
        "fingerprint": FINGERPRINT,
        "port": PORT,
        "protocol": "https",
        "download": False
    }).encode('utf-8')

    for proto in ["https", "http"]:
        try:
            url = f"{proto}://{ip}:{port}/api/localsend/v2/register"
            req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
            ctx = ssl_ctx_client if proto == "https" else None
            with urllib.request.urlopen(req, context=ctx, timeout=2) as resp:
                if resp.status == 200:
                    break
        except Exception:
            pass

import struct
def udp_discovery_listener():
    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    rx.bind(('', PORT))

    if LAN_IP != '0.0.0.0':
        mreq = struct.pack('4s4s', socket.inet_aton(MCAST_ADDR), socket.inet_aton(LAN_IP))
    else:
        mreq = struct.pack('4sL', socket.inet_aton(MCAST_ADDR), socket.INADDR_ANY)
    rx.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    while True:
        try:
            data, (ip, _) = rx.recvfrom(65536)
            try:
                msg = json.loads(data.decode('utf-8'))
                if msg.get("fingerprint") == FINGERPRINT:
                    continue
                # Lorsqu'un iPhone envoie son annonce, on s'enregistre auprès de lui via HTTP
                sender_port = msg.get("port", PORT)
                threading.Thread(target=register_back_to_target, args=(ip, sender_port), daemon=True).start()
            except Exception:
                pass
        except Exception:
            pass

threading.Thread(target=udp_discovery_listener, daemon=True).start()

# ── 4. Serveur HTTP/HTTPS LocalSend Protocol v2 ───────────────────────
sessions = {}

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    pass

class LocalSendHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def _send_json_response(self, data, code=200):
        body = json.dumps(data).encode('utf-8')
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/api/localsend/v2/info':
            self._send_json_response({
                "alias": ALIAS, "version": "2.1", "deviceModel": "Linux",
                "deviceType": "desktop", "fingerprint": FINGERPRINT,
                "port": PORT, "protocol": "https", "download": False
            })
        else:
            self.send_error(404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)

        # 1. Enregistrement direct par scan d'iOS (Subnet Scan / Register)
        if parsed.path == '/api/localsend/v2/register':
            self._send_json_response({
                "alias": ALIAS, "version": "2.1", "deviceModel": "Linux",
                "deviceType": "desktop", "fingerprint": FINGERPRINT,
                "port": PORT, "protocol": "https", "download": False
            })

        # 2. Préparation du transfert de fichiers
        elif parsed.path == '/api/localsend/v2/prepare-upload':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            data = json.loads(body.decode('utf-8'))

            sender_alias = data.get("info", {}).get("alias", "iOS Device")
            session_id = str(uuid.uuid4())
            files_map = {}
            files_info = {}

            for file_id, file_meta in data.get("files", {}).items():
                token = str(uuid.uuid4())
                files_map[file_id] = token
                files_info[file_id] = {
                    "fileName": file_meta.get("fileName"),
                    "size": file_meta.get("size"),
                    "token": token
                }

            sessions[session_id] = {"files": files_info, "alias": sender_alias}
            print(f"RECEIVING\t{sender_alias}", flush=True)
            os.system(f'notify-send "LocalSend" "Transfert en cours depuis {sender_alias}..." -i document-open-recent-symbolic')

            self._send_json_response({"sessionId": session_id, "files": files_map})

        # 3. Réception des données binaires
        elif parsed.path == '/api/localsend/v2/upload':
            query = urllib.parse.parse_qs(parsed.query)
            session_id = query.get('sessionId', [None])[0]
            file_id = query.get('fileId', [None])[0]
            token = query.get('token', [None])[0]

            if not session_id or session_id not in sessions:
                self.send_error(403, "Session invalide")
                return

            session = sessions[session_id]
            file_info = session["files"].get(file_id)
            if not file_info or file_info["token"] != token:
                self.send_error(403, "Token invalide")
                return

            dest_path = os.path.join(SAVE_DIR, file_info["fileName"])
            counter = 1
            base_name, ext = os.path.splitext(file_info["fileName"])
            while os.path.exists(dest_path):
                dest_path = os.path.join(SAVE_DIR, f"{base_name}_{counter}{ext}")
                counter += 1

            content_length = int(self.headers.get('Content-Length', file_info["size"]))
            bytes_read = 0
            with open(dest_path, "wb") as f:
                while bytes_read < content_length:
                    chunk = self.rfile.read(min(65536, content_length - bytes_read))
                    if not chunk:
                        break
                    f.write(chunk)
                    bytes_read += len(chunk)

            sender_alias = session.get("alias", "Appareil inconnu")
            print(f"RECEIVED\t{sender_alias}\t{os.path.basename(dest_path)}", flush=True)
            os.system(f'notify-send "LocalSend" "Reçu : {os.path.basename(dest_path)}" -i emblem-ok-symbolic')
            self.send_response(200)
            self.end_headers()
        else:
            self.send_error(404)

# ── 5. Lancement du Serveur HTTPS ────────────────────────────────────
server = ThreadedHTTPServer(('0.0.0.0', PORT), LocalSendHandler)
ssl_ctx_server = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
ssl_ctx_server.check_hostname = False
ssl_ctx_server.verify_mode = ssl.CERT_NONE
ssl_ctx_server.load_cert_chain(certfile=cert_file, keyfile=key_file)

server.socket = ssl_ctx_server.wrap_socket(server.socket, server_side=True)

print(f"[RECEIVER] Serveur actif pour iOS/Android sur 0.0.0.0:{PORT}")
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
EOF

# exec remplace ce process bash par python3 (même PID, cmdline contenant
# "localsend_receive_XXXXXX.py"). Le trap EXIT ne se déclenchera pas ici
# (exec ne "sort" pas de bash normalement), mais les fichiers temporaires
# sont dans /tmp donc négligeables ; on nettoie aussi les anciens au
# prochain lancement ci-dessous.
find /tmp -maxdepth 1 -name 'localsend_receive_*.py' -mmin +60 -delete 2>/dev/null
exec python3 "$TMP_SCRIPT"