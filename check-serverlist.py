"""
Fragt den Minecraft-Server-List-Ping ab, um zu sehen, was Clients wirklich
angezeigt bekommen: MOTD, Version, Spielerzahl und ob das Icon ausgeliefert wird.
"""
import socket, struct, json, base64, hashlib, sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def varint(n):
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        out += bytes([b | (0x80 if n else 0)])
        if not n:
            return out


def read_varint(sock):
    num, shift = 0, 0
    while True:
        b = sock.recv(1)
        if not b:
            raise EOFError("Verbindung geschlossen")
        num |= (b[0] & 0x7F) << shift
        if not (b[0] & 0x80):
            return num
        shift += 7


def pack_str(s):
    b = s.encode("utf-8")
    return varint(len(b)) + b


HOST, PORT = "127.0.0.1", 25565

with socket.create_connection((HOST, PORT), timeout=10) as s:
    # Handshake, next state = 1 (status)
    hs = (varint(0x00)
          + varint(767)              # Protokollversion
          + pack_str(HOST)
          + struct.pack(">H", PORT)
          + varint(1))
    s.sendall(varint(len(hs)) + hs)
    # Status-Anfrage
    s.sendall(varint(1) + varint(0x00))

    length = read_varint(s)
    pid = read_varint(s)
    slen = read_varint(s)
    data = b""
    while len(data) < slen:
        data += s.recv(slen - len(data))

status = json.loads(data.decode("utf-8"))
desc = status.get("description", "")


def render(desc):
    """§-Codes in Farben umwandeln, damit wir es im Terminal ansehen koennen."""
    colors = {
        "0": "\033[30m", "1": "\033[34m", "2": "\033[32m", "3": "\033[36m",
        "4": "\033[31m", "5": "\033[35m", "6": "\033[33m", "7": "\033[37m",
        "8": "\033[90m", "9": "\033[94m", "a": "\033[92m", "b": "\033[96m",
        "c": "\033[91m", "d": "\033[95m", "e": "\033[93m", "f": "\033[97m",
    }
    if isinstance(desc, dict):
        desc = desc.get("text", "") + desc.get("extra", "") if False else desc.get("text", "")
    out, i = "", 0
    while i < len(desc):
        c = desc[i]
        if c == "\u00a7" and i + 1 < len(desc):
            code = desc[i + 1].lower()
            if code in colors:
                out += colors[code] + " "
                out += colors["f"]
                i += 2
                continue
        out += c
        i += 1
    return "\033[0m" + out


print("=== Was der Client in der Serverliste sieht ===")
print("Version   :", status["version"]["name"])
print("Protokoll :", status["version"]["protocol"])
print("Spieler   : %d von %d" % (status["players"]["online"], status["players"]["max"]))
print("MOTD      :", render(desc) + "\033[0m")
print("MOTD roh  :", repr(desc))
print()

fav = status.get("favicon")
if fav:
    if fav.startswith("data:"):
        fav = fav.split(",", 1)[1]
    png = base64.b64decode(fav)
    print("Icon       : wird ausgeliefert, %d Bytes PNG" % len(png))
    print("             sha1 %s" % hashlib.sha1(png).hexdigest()[:16])
else:
    print("Icon       : FEHLT (kein favicon in der Antwort)")

# Vergleich mit der Datei auf der Platte
with open(r"C:\minecraftai\server\server-icon.png", "rb") as f:
    disk = f.read()
print("             Datei auf Platte: %d Bytes, sha1 %s"
      % (len(disk), hashlib.sha1(disk).hexdigest()[:16]))
print("             identisch:", fav is not None and base64.b64decode(fav) == disk)
