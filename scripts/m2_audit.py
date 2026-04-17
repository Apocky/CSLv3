#!/usr/bin/env python3
"""T25.5 — m₂ audit-chain (Session-11).

Append-only, Ed25519-signed chain of m₂-measurement certificates.
Mirrors the parser/smt_audit.odin pattern but in Python so the
measurement harness is self-contained (no subprocess into parser.exe).

Chain file : .m2-chain/runs.jsonl
Keys       : .m2-chain/keys/{private,public}.key (32-byte raw Ed25519)

Each entry :
  {seq, prev_hash, run_id, timestamp, file_hash, paraphrase_hash,
   model_hash, model_name, m2_value, m2_ci_low, m2_ci_high,
   seed, backend, signature}

Canonical form for signing = pipe-joined fields excluding signature.
Signature verifies by reconstructing the canonical string and verifying
Ed25519 against the stored public key.

Usage :
  python scripts/m2_audit.py --append <baseline.json>   → append one run
  python scripts/m2_audit.py --verify                    → replay-verify
  python scripts/m2_audit.py --show                      → list entries
  python scripts/m2_audit.py --init                      → keypair-bootstrap
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import sys
import uuid
from dataclasses import dataclass, asdict
from pathlib import Path

ROOT       = Path(__file__).resolve().parent.parent
CHAIN_DIR  = ROOT / ".m2-chain"
KEYS_DIR   = CHAIN_DIR / "keys"
CHAIN_FILE = CHAIN_DIR / "runs.jsonl"
PRIV_KEY   = KEYS_DIR / "private.key"
PUB_KEY    = KEYS_DIR / "public.key"


# ---------- Key management ----------

def ensure_keypair() -> None:
    """Generate dev-stub Ed25519 keypair if absent."""
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization

    KEYS_DIR.mkdir(parents=True, exist_ok=True)
    if PRIV_KEY.exists() and PUB_KEY.exists():
        return
    sk = Ed25519PrivateKey.generate()
    priv_bytes = sk.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    pk = sk.public_key()
    pub_bytes = pk.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    PRIV_KEY.write_bytes(priv_bytes)
    PUB_KEY.write_bytes(pub_bytes)
    print(f"[init] wrote dev-stub keypair under {KEYS_DIR}")


def load_private_key():
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    return Ed25519PrivateKey.from_private_bytes(PRIV_KEY.read_bytes())


def load_public_key():
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    return Ed25519PublicKey.from_public_bytes(PUB_KEY.read_bytes())


# ---------- Chain entry ----------

@dataclass
class AuditEntry:
    seq:              int
    prev_hash:        str
    run_id:           str
    timestamp:        str
    file:             str
    file_hash:        str
    paraphrase:       str
    paraphrase_hash:  str
    model_key:        str
    model_name:       str
    model_hash:       str
    m2_value:         float
    m2_ci_low:        float
    m2_ci_high:       float
    seed:             int
    backend:          str
    signature:        str = ""


def sha256_of_file(path: Path) -> str:
    if not path.exists():
        return "missing"
    h = hashlib.sha256()
    with path.open("rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def canonical_bytes(e: AuditEntry) -> bytes:
    fields = [
        str(e.seq), e.prev_hash, e.run_id, e.timestamp,
        e.file, e.file_hash, e.paraphrase, e.paraphrase_hash,
        e.model_key, e.model_name, e.model_hash,
        f"{e.m2_value:.6f}", f"{e.m2_ci_low:.6f}", f"{e.m2_ci_high:.6f}",
        str(e.seed), e.backend,
    ]
    return "|".join(fields).encode("utf-8")


def entry_hash(e: AuditEntry) -> str:
    h = hashlib.sha256()
    h.update(canonical_bytes(e))
    h.update(b"|")
    h.update(e.signature.encode("utf-8"))
    return h.hexdigest()


def sign_entry(e: AuditEntry) -> None:
    sk = load_private_key()
    sig = sk.sign(canonical_bytes(e))
    e.signature = base64.b64encode(sig).decode("ascii")


def verify_entry(e: AuditEntry, pk=None) -> bool:
    from cryptography.exceptions import InvalidSignature
    if pk is None:
        pk = load_public_key()
    try:
        pk.verify(base64.b64decode(e.signature), canonical_bytes(e))
        return True
    except (InvalidSignature, ValueError):
        return False


# ---------- Chain ops ----------

def chain_tail() -> tuple[int, str]:
    """Return (last-seq, last-hash). Returns (-1, "") if chain is empty."""
    if not CHAIN_FILE.exists():
        return -1, ""
    last_seq = -1
    last_hash = ""
    for line in CHAIN_FILE.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        if d["seq"] > last_seq:
            last_seq = d["seq"]
            last_hash = entry_hash(AuditEntry(**d))
    return last_seq, last_hash


def write_genesis() -> None:
    e = AuditEntry(
        seq=0,
        prev_hash="",
        run_id="GENESIS",
        timestamp=dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        file="GENESIS",
        file_hash="0" * 64,
        paraphrase="GENESIS",
        paraphrase_hash="0" * 64,
        model_key="none",
        model_name="none",
        model_hash="0" * 64,
        m2_value=0.0,
        m2_ci_low=0.0,
        m2_ci_high=0.0,
        seed=0,
        backend="genesis",
    )
    sign_entry(e)
    CHAIN_DIR.mkdir(parents=True, exist_ok=True)
    with CHAIN_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(asdict(e), ensure_ascii=False) + "\n")


def append_measurement(
    file_path: Path,
    paraphrase_path: Path,
    model_key: str,
    model_name: str,
    model_hash: str,
    m2: float, lo: float, hi: float,
    seed: int, backend: str,
) -> AuditEntry:
    ensure_keypair()
    if not CHAIN_FILE.exists():
        write_genesis()

    seq, prev = chain_tail()
    e = AuditEntry(
        seq=seq + 1,
        prev_hash=prev,
        run_id=str(uuid.uuid4()),
        timestamp=dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        file=str(file_path.name),
        file_hash=sha256_of_file(file_path),
        paraphrase=str(paraphrase_path.name),
        paraphrase_hash=sha256_of_file(paraphrase_path),
        model_key=model_key,
        model_name=model_name,
        model_hash=model_hash,
        m2_value=m2,
        m2_ci_low=lo,
        m2_ci_high=hi,
        seed=seed,
        backend=backend,
    )
    sign_entry(e)
    with CHAIN_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(asdict(e), ensure_ascii=False) + "\n")
    return e


def verify_chain() -> tuple[bool, int, str]:
    """Walk the chain, verify every signature + prev_hash linkage."""
    if not CHAIN_FILE.exists():
        return True, 0, "empty"
    pk = load_public_key()

    prev_hash = ""
    seq_expected = 0
    n_ok = 0
    for i, line in enumerate(CHAIN_FILE.read_text(encoding="utf-8").splitlines()):
        if not line.strip():
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError as exc:
            return False, n_ok, f"line {i}: invalid JSON: {exc}"
        e = AuditEntry(**d)
        if e.seq != seq_expected:
            return False, n_ok, f"line {i}: seq {e.seq} != {seq_expected}"
        if e.prev_hash != prev_hash:
            return False, n_ok, f"line {i}: prev_hash mismatch"
        if not verify_entry(e, pk):
            return False, n_ok, f"line {i}: signature FAIL"
        prev_hash = entry_hash(e)
        seq_expected += 1
        n_ok += 1
    return True, n_ok, "OK"


# ---------- CLI ----------

def cmd_init(args) -> int:
    ensure_keypair()
    if not CHAIN_FILE.exists():
        write_genesis()
        print(f"[init] wrote genesis entry to {CHAIN_FILE}")
    else:
        print(f"[init] chain already exists at {CHAIN_FILE}")
    return 0


def cmd_append(args) -> int:
    baseline_path = Path(args.append)
    if not baseline_path.exists():
        print(f"baseline JSON not found: {baseline_path}", file=sys.stderr)
        return 2
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))

    ensure_keypair()
    if not CHAIN_FILE.exists():
        write_genesis()

    count = 0
    for m in baseline.get("measurements", []):
        file_path = ROOT / "eval" / m["file"]
        para_key = m["paraphrase"]
        para_path = ROOT / "eval" / "paraphrases" / f"{para_key}.en"
        if not para_path.exists():
            # Fall-back to legacy _EN.md
            legacy = list(ROOT.glob(f"eval/{para_key}_*_EN.md"))
            if legacy:
                para_path = legacy[0]
        e = append_measurement(
            file_path, para_path,
            m["model_key"], m["model_name"], m.get("model_sha", "unknown"),
            m["m2"], m["m2_ci_low"], m["m2_ci_high"],
            m["seed"], m.get("backend", "unknown"),
        )
        count += 1
        print(f"[append] seq={e.seq} {m['model_key']:6s} {m['file']:30s} m2={m['m2']:.4f}")
    print(f"\nappended {count} entries ; chain at {CHAIN_FILE}")
    return 0


def cmd_verify(args) -> int:
    ok, n, msg = verify_chain()
    print(f"chain {CHAIN_FILE}: {n} entries verified, status={msg}")
    return 0 if ok else 1


def cmd_show(args) -> int:
    if not CHAIN_FILE.exists():
        print(f"(no chain at {CHAIN_FILE})")
        return 0
    for i, line in enumerate(CHAIN_FILE.read_text(encoding="utf-8").splitlines()):
        if not line.strip():
            continue
        d = json.loads(line)
        if d["seq"] == 0:
            print(f"[{d['seq']:3d}] GENESIS")
            continue
        print(f"[{d['seq']:3d}] {d['timestamp']} {d['model_key']:6s} "
              f"{d['file']:30s} m2={d['m2_value']:.4f} "
              f"CI=[{d['m2_ci_low']:.4f},{d['m2_ci_high']:.4f}] "
              f"{d['backend']}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=False)
    g.add_argument("--init", action="store_true", help="bootstrap keypair + genesis")
    g.add_argument("--append", help="append measurements from m2_baseline.json")
    g.add_argument("--verify", action="store_true", help="walk chain + verify signatures")
    g.add_argument("--show", action="store_true", help="list chain entries")
    args = ap.parse_args()

    try:
        import cryptography  # noqa: F401
    except ImportError:
        print("ERROR: pip install cryptography", file=sys.stderr)
        return 2

    if args.init:
        return cmd_init(args)
    if args.append:
        return cmd_append(args)
    if args.verify:
        return cmd_verify(args)
    if args.show:
        return cmd_show(args)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
