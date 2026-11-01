#!/usr/bin/env python3
"""Firmador de APK (APK Signature Scheme v2) sin Android SDK. Sustituye a build-tools/apksigner
para que Godot pueda exportar a Android en un entorno sin el SDK oficial.
  apksigner_v2.py sign --ks KEYSTORE --ks-pass pass:XXX [--ks-key-alias A] [--verbose] APK
  apksigner_v2.py verify [--verbose] APK
  apksigner_v2.py --version
"""
import hashlib, struct, sys, zipfile
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import pkcs12

MAGIC = b"APK Sig Block 42"
V2_ID = 0x7109871a
ALGO = 0x0103  # RSASSA-PKCS1-v1_5 con SHA-256
CH = 1024 * 1024


def lp(b):
    return struct.pack("<I", len(b)) + b


def locate(d):
    i = d.rfind(b"PK\x05\x06")
    cd_size, cd_off = struct.unpack("<II", d[i + 12:i + 20])
    return i, cd_off, cd_size


def digest(sections):
    out = b""; n = 0
    for s in sections:
        for k in range(0, len(s), CH):
            c = s[k:k + CH]
            out += hashlib.sha256(b"\xa5" + struct.pack("<I", len(c)) + c).digest(); n += 1
    return hashlib.sha256(b"\x5a" + struct.pack("<I", n) + out).digest()


def split(d):
    eocd, cd_off, cd_size = locate(d)
    if d[cd_off - 16:cd_off] == MAGIC:  # ya firmado: se quita el bloque antiguo
        blk = struct.unpack("<Q", d[cd_off - 24:cd_off - 16])[0]
        start = cd_off - blk - 8
        d = d[:start] + d[cd_off:]
        eocd, cd_off, cd_size = locate(d)
    return d, eocd, cd_off, cd_size


def sign(apk, ks, pw):
    d = open(apk, "rb").read()
    d, eocd, cd_off, cd_size = split(d)
    key, cert, _ = pkcs12.load_key_and_certificates(open(ks, "rb").read(), pw.encode())
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    pub = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    sections = [d[:cd_off], d[cd_off:eocd], d[eocd:]]
    dg = digest(sections)
    signed = lp(lp(struct.pack("<I", ALGO) + lp(dg))) + lp(lp(cert_der)) + lp(b"")
    sig = key.sign(signed, padding.PKCS1v15(), hashes.SHA256())
    signer = lp(signed) + lp(lp(struct.pack("<I", ALGO) + lp(sig))) + lp(pub)
    value = lp(lp(signer))
    pair = struct.pack("<Q", 4 + len(value)) + struct.pack("<I", V2_ID) + value
    block = struct.pack("<Q", len(pair) + 8 + 16) + pair + struct.pack("<Q", len(pair) + 8 + 16) + MAGIC
    eo = bytearray(d[eocd:])
    eo[16:20] = struct.pack("<I", cd_off + len(block))
    open(apk, "wb").write(d[:cd_off] + block + d[cd_off:eocd] + bytes(eo))


def verify(apk):
    d = open(apk, "rb").read()
    eocd, cd_off, cd_size = locate(d)
    if d[cd_off - 16:cd_off] != MAGIC:
        return False, "sin bloque de firma v2"
    blk = struct.unpack("<Q", d[cd_off - 24:cd_off - 16])[0]
    start = cd_off - blk - 8
    pairs = d[start + 8:cd_off - 24]
    id_, = struct.unpack("<I", pairs[8:12]); value = pairs[12:]
    if id_ != V2_ID:
        return False, "id inesperado"
    # signers -> signer -> signed data
    p = 8  # lp(lp(signer)): longitud total + longitud de signer
    signer = value[8:]
    sd_len, = struct.unpack("<I", signer[:4]); signed = signer[4:4 + sd_len]
    rest = signer[4 + sd_len:]
    dg_in_signed = signed[4 + 4 + 4 + 4:4 + 4 + 4 + 4 + 32]
    orig = d[:start] + d[cd_off:]
    e2 = orig.rfind(b"PK\x05\x06"); c2 = start
    eo = bytearray(orig[e2:]); eo[16:20] = struct.pack("<I", start)
    ok = digest([orig[:c2], orig[c2:e2], bytes(eo)]) == dg_in_signed
    return ok, "digest %s" % ("correcto" if ok else "NO coincide")


def main(a):
    if a and a[0] == "--version":
        print("34.0.0"); return 0
    if a[0] == "sign":
        ks = pw = None
        for i, x in enumerate(a):
            if x == "--ks": ks = a[i + 1]
            if x == "--ks-pass": pw = a[i + 1].split("pass:", 1)[1]
        sign(a[-1], ks, pw); print("Signed"); return 0
    if a[0] == "verify":
        ok, msg = verify(a[-1]); print("Verifies" if ok else "DOES NOT VERIFY: " + msg)
        return 0 if ok else 1
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
