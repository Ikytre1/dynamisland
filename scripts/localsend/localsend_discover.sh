#!/bin/bash
# LocalSend discovery: UDP multicast + HTTP subnet scan fallback (Loop until found or 10s timeout)

python3 - <<'EOF'
import socket, json, time, struct, re, subprocess, asyncio, ssl, sys

def log(msg):
    print(f"[DEBUG-DISCOVER] {msg}", file=sys.stderr, flush=True)

MCAST = '224.0.0.167'
PORT  = 53317
TIMEOUT_GLOBAL = 10.0  # Durée maximale de recherche en secondes

try:
    out = subprocess.check_output(["ip", "-4", "addr"], text=True)
    local_ips = set(re.findall(r'inet (\d+\.\d+\.\d+\.\d+)', out))
    log(f"IPs locales détectées: {local_ips}")

    route_out = subprocess.check_output(["ip", "route", "get", MCAST], text=True)
    src_m = re.search(r'src (\d+\.\d+\.\d+\.\d+)', route_out)
    lan_ip = src_m.group(1) if src_m else ''
    log(f"IP LAN routable vers multicast: '{lan_ip}'")
except Exception as e:
    log(f"Erreur lors de la détection réseau: {e}")
    local_ips = set()
    lan_ip = ''

seen = set()

def emit(ip, alias, device_type="desktop"):
    if ip not in seen and ip not in local_ips:
        seen.add(ip)
        log(f"==== APPAREIL TROUVÉ ==== IP: {ip}, Alias: {alias}, Type: {device_type}")
        print(f"{alias}\t{ip}\t{device_type}", flush=True)

# ── Configuration des sockets UDP Multicast ───────────────────────────
rx = None
tx = None
try:
    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    rx.bind(('', PORT))
    
    if lan_ip:
        mreq = struct.pack('4s4s', socket.inet_aton(MCAST), socket.inet_aton(lan_ip))
    else:
        mreq = struct.pack('4sL', socket.inet_aton(MCAST), socket.INADDR_ANY)
        
    rx.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    rx.settimeout(0.1)
    
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 4)
    if lan_ip:
        tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(lan_ip))
except Exception as e:
    log(f"Erreur d'initialisation UDP: {e}")

announce = json.dumps({
    "alias": "QuickShell Stash", "version": "2.1",
    "deviceModel": None, "deviceType": "headless",
    "fingerprint": "qs_stash_discover",
    "port": PORT, "protocol": "https",
    "download": False, "announce": True
}).encode()

# ── Helper HTTPS Scanner ─────────────────────────────────────────────
prefix = '.'.join(lan_ip.split('.')[:3]) if lan_ip else ''
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

async def probe(ip):
    if ip in local_ips or ip in seen:
        return
    try:
        r, w = await asyncio.wait_for(asyncio.open_connection(ip, PORT, ssl=ctx), timeout=0.5)
        w.write(f"GET /api/localsend/v2/info HTTP/1.0\r\nHost: {ip}\r\nConnection: close\r\n\r\n".encode())
        await w.drain()
        data = await asyncio.wait_for(r.read(4096), timeout=0.5)
        w.close()
        body = data.split(b'\r\n\r\n', 1)
        if len(body) < 2:
            return
        info = json.loads(body[1].decode())
        dev_type = info.get('deviceType', info.get('deviceModel', 'desktop'))
        emit(ip, info.get('alias', 'Unknown'), dev_type)
    except:
        pass

async def scan_subnet():
    if not prefix:
        return
    tasks = [probe(f"{prefix}.{i}") for i in range(1, 255)]
    await asyncio.gather(*tasks)

# ── Boucle Principale avec Timeout Global de 10s ─────────────────────
start_time = time.time()
log(f"Démarrage de la recherche continue (Timeout: {TIMEOUT_GLOBAL}s)...")

iteration = 0
while time.time() - start_time < TIMEOUT_GLOBAL:
    iteration += 1
    log(f"--- Cycle de recherche #{iteration} ---")

    # 1. Annonce UDP & Ecoute
    if tx and rx:
        try:
            tx.sendto(announce, (MCAST, PORT))
            log(f"Paquet UDP Announce envoyé à {MCAST}:{PORT}")
            
            udp_deadline = time.time() + 0.8
            while time.time() < udp_deadline:
                try:
                    data, (ip, _) = rx.recvfrom(65536)
                    if ip in local_ips:
                        continue
                    try:
                        info = json.loads(data.decode())
                    except:
                        continue
                    
                    if info.get('fingerprint') == 'qs_stash_discover':
                        continue
                    dev_type = info.get('deviceType', info.get('deviceModel', 'desktop'))
                    emit(ip, info.get('alias', 'Unknown'), dev_type)
                    if seen:
                        break
                except socket.timeout:
                    pass
        except Exception as e:
            log(f"Erreur durant écoute UDP: {e}")

    if seen:
        log("Appareil(s) trouvé(s) via Multicast. Fin de la recherche.")
        sys.exit(0)

    # 2. Fallback Scan Subnet HTTPS
    log("Démarrage balayage HTTPS du sous-réseau...")
    asyncio.run(scan_subnet())

    if seen:
        log("Appareil(s) trouvé(s) via Scan HTTPS. Fin de la recherche.")
        sys.exit(0)

    time.sleep(0.2)

log("Timeout de 10s atteint. Aucun appareil trouvé.")
sys.exit(0)
EOF