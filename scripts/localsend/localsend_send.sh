#!/bin/bash
# Send a file to a LocalSend target with auto fallback between HTTPS and HTTP
# Usage: localsend_send.sh <file> <target-ip>

FILE="$1"
TARGET="$2"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    notify-send "LocalSend" "Fichier non trouvé" -i dialog-error; exit 1
fi
if [ -z "$TARGET" ]; then
    notify-send "LocalSend" "Cible non spécifiée" -i dialog-error; exit 1
fi

notify-send "LocalSend" "Demande d'envoi vers $TARGET..." -t 3000

python3 - <<EOF
import sys, os, json, ssl, urllib.request, hashlib
from datetime import datetime, timedelta, timezone

target = "$TARGET"
port = 53317
file_path = "$FILE"
file_name = os.path.basename(file_path)
file_size = os.path.getsize(file_path)

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
        x509.NameAttribute(NameOID.COMMON_NAME, "LocalSend Client")
    ])

    san = x509.SubjectAlternativeName([
        x509.DNSName("localhost"),
        x509.IPAddress(ipaddress.ip_address("127.0.0.1"))
    ])
    
    key_usage = x509.KeyUsage(
        digital_signature=True, key_encipherment=True,
        content_commitment=False, data_encipherment=False, key_agreement=False,
        key_cert_sign=False, crl_sign=False, encipher_only=False, decipher_only=False
    )
    
    ext_key_usage = x509.ExtendedKeyUsage([
        ExtendedKeyUsageOID.CLIENT_AUTH,
        ExtendedKeyUsageOID.SERVER_AUTH
    ])

    cert = x509.CertificateBuilder()\
        .subject_name(subject)\
        .issuer_name(issuer)\
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
    fingerprint = hashlib.sha256(cert_der).hexdigest().lower()

file_id = f"qs_{hashlib.md5(file_name.encode()).hexdigest()[:8]}"

payload = {
    "info": {
        "alias": "QuickShell",
        "version": "2.1",
        "deviceModel": "Linux",
        "deviceType": "desktop",
        "fingerprint": fingerprint,
        "port": port,
        "protocol": "https",
        "download": False
    },
    "files": {
        file_id: {
            "id": file_id,
            "fileName": file_name,
            "size": file_size,
            "fileType": "other"
        }
    }
}

ssl_ctx = ssl.create_default_context()
ssl_ctx.check_hostname = False
ssl_ctx.verify_mode = ssl.CERT_NONE
ssl_ctx.load_cert_chain(certfile=cert_file, keyfile=key_file)

# On essaie d'abord HTTPS, et si l'iPhone répond en HTTP simple, on bascule automatiquement
success = False
for proto in ["https", "http"]:
    url = f"{proto}://{target}:{port}/api/localsend/v2/prepare-upload"
    req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers={"Content-Type": "application/json"})
    ctx = ssl_ctx if proto == "https" else None
    try:
        print(f"[DEBUG-SEND] Essai avec le protocole : {proto.upper()}", file=sys.stderr)
        with urllib.request.urlopen(req, context=ctx, timeout=8) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            session_id = data.get("sessionId")
            files_map = data.get("files", {})
            token = files_map.get(file_id) if isinstance(files_map, dict) else None
            
            if session_id and token:
                upload_url = f"{proto}://{target}:{port}/api/localsend/v2/upload?sessionId={session_id}&fileId={file_id}&token={token}"
                with open(file_path, "rb") as fp:
                    up_req = urllib.request.Request(upload_url, data=fp.read(), headers={"Content-Type": "application/octet-stream"})
                    with urllib.request.urlopen(up_req, context=ctx, timeout=300) as up_resp:
                        if up_resp.status == 200:
                            os.system(f'notify-send "LocalSend" "Envoyé : {file_name}" -i emblem-ok-symbolic')
                            success = True
                            break
    except Exception as e:
        print(f"[DEBUG-SEND] Échec en {proto.upper()}: {e}", file=sys.stderr)

if not success:
    os.system('notify-send "LocalSend - Échec" "Transfert refusé ou non joignable" -i dialog-error')
    sys.exit(1)
EOF