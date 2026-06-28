#!/usr/bin/env python3
"""Experiment registry & immutable result ledger (BUILD-PLAN R3).

ONE machine-readable row per experiment (`experiments/<id>.yaml`) + a flat rollup
(`index.csv`). This is the auditability spine for the mutual-skepticism trust contract:
every sweep / backtest / MT5 run records its provenance (commit, data, .set, cost model,
search width) and its decision (LOCK / REJECT / RESEARCH-ONLY / STOP) so no claim is an
assertion — it is a reproducible row.

Field names for the overfitting-gate block deliberately mirror `research/stats/gate.py`
(`n_trials`, `sr_trial_std`, `psr`/psr0, `dsr`, `mintrl`, `verdict`) so a registry row and
a gate run speak the same language.

CLI:
    python research/registry/registry.py rebuild     # regenerate index.csv from experiments/*.yaml
    python research/registry/registry.py validate     # check every row against the schema
    python research/registry/registry.py list          # one-line summary per row

API:
    from registry import make_record, append_row, rebuild_index, sha256_file
    rid = append_row(make_record(strategy="kenkem", symbol="XAUUSD", timeframe="M1",
                                 decision="LOCK", label="d5-e4long", ...))

IDs are DETERMINISTIC (strategy+symbol+timeframe+decision+label) — never time/random — so
re-running a back-fill is idempotent (same id -> same file, overwritten in place).
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - yaml ships in the kenkem env
    yaml = None

HERE = os.path.dirname(os.path.abspath(__file__))
EXPERIMENTS_DIR = os.path.join(HERE, "experiments")
INDEX_CSV = os.path.join(HERE, "index.csv")

SCHEMA_VERSION = 1
DECISIONS = ("LOCK", "REJECT", "RESEARCH-ONLY", "STOP")

# Required top-level identity/provenance fields (value may be null where genuinely unknown,
# but the KEY must be present so a blank is an explicit "unknown", never a silent zero).
REQUIRED = (
    "schema_version", "experiment_id", "date", "hypothesis_id", "strategy", "symbol",
    "timeframe", "train_start", "train_end", "oos_start", "oos_end", "commit_hash",
    "data_source", "data_sha256", "set_path", "set_sha256", "cost_model", "n_trials",
    "sr_trial_std", "metrics", "gate", "mt5_confirmed", "artifacts", "decision", "notes",
    "source_refs",
)
METRIC_KEYS = ("net_usd", "pf", "max_dd_pct", "sharpe", "n_trades", "win_pct")
GATE_KEYS = ("psr", "dsr", "mintrl", "mintrl_sufficient", "pbo", "verdict")

# Flat column order for index.csv (load-bearing: keep stable so diffs stay readable).
INDEX_COLUMNS = (
    "experiment_id", "date", "decision", "strategy", "symbol", "timeframe",
    "hypothesis_id", "net_usd", "pf", "max_dd_pct", "sharpe", "n_trades", "n_trials",
    "sr_trial_std", "psr", "dsr", "mintrl", "mintrl_sufficient", "pbo", "gate_verdict",
    "mt5_confirmed", "commit_hash", "set_path", "supersedes", "superseded_by", "notes",
)


def _require_yaml():
    if yaml is None:
        sys.exit("PyYAML not available — run under `conda run -n kenkem python`.")


def slugify(s) -> str:
    s = "" if s is None else str(s)
    s = s.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def make_experiment_id(strategy, symbol, timeframe, decision, label) -> str:
    """Deterministic id from strategy+symbol+timeframe+decision (+ a label to disambiguate
    sibling experiments, e.g. several REJECTs on the same symbol). No time, no random."""
    parts = [slugify(p) for p in (strategy, symbol, timeframe, decision, label)]
    return "-".join(p for p in parts if p)


def sha256_file(path):
    """Hex sha256 of a file for artifact provenance (data/.set hashing going forward).
    Returns None if the path is missing — back-fill rows legitimately carry null hashes
    because the artifact-at-lock-time is not the current file."""
    if not path or not os.path.isfile(path):
        return None
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def make_record(*, strategy, symbol, timeframe, decision, label,
                date=None, hypothesis_id=None, train_start=None, train_end=None,
                oos_start=None, oos_end=None, commit_hash=None, data_source=None,
                data_sha256=None, set_path=None, set_sha256=None, cost_model=None,
                n_trials=None, sr_trial_std=None, net_usd=None, pf=None, max_dd_pct=None,
                sharpe=None, n_trades=None, win_pct=None, psr=None, dsr=None, mintrl=None,
                mintrl_sufficient=None, pbo=None, gate_verdict=None, mt5_confirmed=None,
                artifacts=None, supersedes=None, superseded_by=None, notes=None,
                source_refs=None, experiment_id=None):
    """Normalize keyword args into a registry record (nested metrics/gate blocks).
    Anything not supplied stays None (-> yaml null / blank csv) — blank != zero."""
    if decision not in DECISIONS:
        raise ValueError(f"decision must be one of {DECISIONS}, got {decision!r}")
    rid = experiment_id or make_experiment_id(strategy, symbol, timeframe, decision, label)
    rec = {
        "schema_version": SCHEMA_VERSION,
        "experiment_id": rid,
        "date": date,
        "hypothesis_id": hypothesis_id,
        "strategy": strategy,
        "symbol": symbol,
        "timeframe": timeframe,
        "train_start": train_start,
        "train_end": train_end,
        "oos_start": oos_start,
        "oos_end": oos_end,
        "commit_hash": commit_hash,
        "data_source": data_source,
        "data_sha256": data_sha256,
        "set_path": set_path,
        "set_sha256": set_sha256,
        "cost_model": cost_model,
        "n_trials": n_trials,
        "sr_trial_std": sr_trial_std,
        "metrics": {
            "net_usd": net_usd, "pf": pf, "max_dd_pct": max_dd_pct,
            "sharpe": sharpe, "n_trades": n_trades, "win_pct": win_pct,
        },
        "gate": {
            "psr": psr, "dsr": dsr, "mintrl": mintrl,
            "mintrl_sufficient": mintrl_sufficient, "pbo": pbo, "verdict": gate_verdict,
        },
        "mt5_confirmed": mt5_confirmed,
        "artifacts": list(artifacts) if artifacts else [],
        "decision": decision,
        "supersedes": supersedes,
        "superseded_by": superseded_by,
        "notes": notes,
        "source_refs": list(source_refs) if source_refs else [],
    }
    return rec


def validate(rec):
    """Return a list of human-readable problems (empty list == valid)."""
    problems = []
    for k in REQUIRED:
        if k not in rec:
            problems.append(f"missing required field: {k}")
    if rec.get("decision") not in DECISIONS:
        problems.append(f"decision {rec.get('decision')!r} not in {DECISIONS}")
    m = rec.get("metrics") or {}
    if not isinstance(m, dict):
        problems.append("metrics must be a mapping")
    else:
        for k in METRIC_KEYS:
            if k not in m:
                problems.append(f"metrics missing key: {k}")
    g = rec.get("gate") or {}
    if not isinstance(g, dict):
        problems.append("gate must be a mapping")
    else:
        for k in GATE_KEYS:
            if k not in g:
                problems.append(f"gate missing key: {k}")
        v = g.get("verdict")
        if v not in (None, "PASS", "WARN", "FAIL"):
            problems.append(f"gate.verdict {v!r} not in PASS/WARN/FAIL/null")
    return problems


def append_row(rec, experiments_dir=EXPERIMENTS_DIR, rebuild=True):
    """Write/overwrite experiments/<id>.yaml for one record, then (optionally) rebuild index.
    Idempotent: the id is content-derived, so re-appending the same logical experiment
    overwrites the same file. Returns the experiment_id."""
    _require_yaml()
    problems = validate(rec)
    if problems:
        raise ValueError("invalid record: " + "; ".join(problems))
    os.makedirs(experiments_dir, exist_ok=True)
    rid = rec["experiment_id"]
    path = os.path.join(experiments_dir, rid + ".yaml")
    with open(path, "w") as f:
        yaml.safe_dump(rec, f, sort_keys=False, default_flow_style=False, allow_unicode=True)
    if rebuild:
        rebuild_index(experiments_dir)
    return rid


def load_all(experiments_dir=EXPERIMENTS_DIR):
    """Load every experiments/*.yaml as a list of records, sorted by (date, id)."""
    _require_yaml()
    recs = []
    if not os.path.isdir(experiments_dir):
        return recs
    for fn in sorted(os.listdir(experiments_dir)):
        if not fn.endswith((".yaml", ".yml")):
            continue
        with open(os.path.join(experiments_dir, fn)) as f:
            recs.append(yaml.safe_load(f))
    recs.sort(key=lambda r: (str(r.get("date") or ""), str(r.get("experiment_id") or "")))
    return recs


def _csv_val(v):
    """None -> '' (explicit unknown), bool -> true/false, else str(v)."""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def _flatten(rec):
    m = rec.get("metrics") or {}
    g = rec.get("gate") or {}
    notes = (rec.get("notes") or "").replace("\n", " ").strip()
    if len(notes) > 160:
        notes = notes[:157] + "..."
    flat = {
        "experiment_id": rec.get("experiment_id"),
        "date": rec.get("date"),
        "decision": rec.get("decision"),
        "strategy": rec.get("strategy"),
        "symbol": rec.get("symbol"),
        "timeframe": rec.get("timeframe"),
        "hypothesis_id": rec.get("hypothesis_id"),
        "net_usd": m.get("net_usd"),
        "pf": m.get("pf"),
        "max_dd_pct": m.get("max_dd_pct"),
        "sharpe": m.get("sharpe"),
        "n_trades": m.get("n_trades"),
        "n_trials": rec.get("n_trials"),
        "sr_trial_std": rec.get("sr_trial_std"),
        "psr": g.get("psr"),
        "dsr": g.get("dsr"),
        "mintrl": g.get("mintrl"),
        "mintrl_sufficient": g.get("mintrl_sufficient"),
        "pbo": g.get("pbo"),
        "gate_verdict": g.get("verdict"),
        "mt5_confirmed": rec.get("mt5_confirmed"),
        "commit_hash": rec.get("commit_hash"),
        "set_path": rec.get("set_path"),
        "supersedes": rec.get("supersedes"),
        "superseded_by": rec.get("superseded_by"),
        "notes": notes,
    }
    return {k: _csv_val(flat.get(k)) for k in INDEX_COLUMNS}


def rebuild_index(experiments_dir=EXPERIMENTS_DIR, index_csv=INDEX_CSV):
    """Regenerate index.csv deterministically from every experiments/*.yaml. Returns row count."""
    recs = load_all(experiments_dir)
    with open(index_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(INDEX_COLUMNS))
        w.writeheader()
        for rec in recs:
            w.writerow(_flatten(rec))
    return len(recs)


def _cmd_rebuild(_):
    n = rebuild_index()
    print(f"rebuilt {INDEX_CSV} from {n} experiment row(s)")


def _cmd_validate(_):
    recs = load_all()
    bad = 0
    for rec in recs:
        problems = validate(rec)
        rid = rec.get("experiment_id", "<no id>")
        if problems:
            bad += 1
            print(f"FAIL {rid}: " + "; ".join(problems))
        else:
            print(f"ok   {rid}")
    print(f"\n{len(recs) - bad}/{len(recs)} valid")
    return 1 if bad else 0


def _cmd_list(_):
    for rec in load_all():
        m = rec.get("metrics") or {}
        print(f"{rec.get('decision','?'):14} {rec.get('experiment_id')}  "
              f"net={m.get('net_usd')} pf={m.get('pf')} n={m.get('n_trades')}")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Experiment registry / immutable result ledger (R3)")
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("rebuild", help="regenerate index.csv from experiments/*.yaml").set_defaults(fn=_cmd_rebuild)
    sub.add_parser("validate", help="check every row against the schema").set_defaults(fn=_cmd_validate)
    sub.add_parser("list", help="one-line summary per row").set_defaults(fn=_cmd_list)
    args = ap.parse_args(argv)
    if not getattr(args, "fn", None):
        # default action: rebuild (so `python registry.py` regenerates the rollup)
        return _cmd_rebuild(args)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main() or 0)
