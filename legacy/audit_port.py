#!/usr/bin/env python3
"""Inventory legacy changes against pinned upstream trees, without fetching blobs.

This is a planning report, not proof that a patch or browser works on an old OS.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys


def git(repo, *arguments):
    return subprocess.check_output(["git", "-C", str(repo), *arguments])


def tree_entries(repo, revision, paths):
    entries = {}
    if not paths:
        return entries
    raw = git(repo, "ls-tree", "-r", "-z", revision, "--", *paths)
    for record in raw.split(b"\0"):
        if record:
            metadata, path = record.split(b"\t", 1)
            mode, kind, oid = metadata.decode("ascii").split()
            entries[path.decode("utf-8", "surrogateescape")] = (mode, kind, oid)
    return entries


def audit(repo, lock):
    revisions = {}
    for key in ("legacy_base", "legacy_port", "target"):
        revision = lock[key]["revision"]
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError(f"{key} must pin a full SHA-1 commit")
        git(repo, "cat-file", "-e", revision + "^{commit}")
        revisions[key] = revision
    raw = git(repo, "diff", "--name-status", "--no-renames", "-z",
              revisions["legacy_base"], revisions["legacy_port"])
    fields = raw.rstrip(b"\0").split(b"\0") if raw else []
    if len(fields) % 2:
        raise ValueError("Unexpected git name-status format")
    changes = [(fields[i].decode("ascii"), fields[i + 1].decode("utf-8", "surrogateescape"))
               for i in range(0, len(fields), 2)]
    paths = [path for _, path in changes]
    trees = {key: tree_entries(repo, revision, paths) for key, revision in revisions.items()}
    files = []
    for change, path in changes:
        original = trees["legacy_base"].get(path)
        legacy = trees["legacy_port"].get(path)
        target = trees["target"].get(path)
        if target == legacy:
            disposition = "already_in_target"
        elif original is None and target is None:
            disposition = "legacy_addition"
        elif target is None:
            disposition = "upstream_removed"
        elif target == original:
            disposition = "upstream_unchanged"
        else:
            disposition = "upstream_changed"
        files.append({"path": path, "change": change, "disposition": disposition})
    return {"comparison": "Legacy delta against the unmodified target upstream; not a port completion report",
            "revisions": revisions, "summary": dict(sorted(Counter(f["disposition"] for f in files).items())),
            "total_files": len(files), "files": files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--lock", type=Path, default=Path(__file__).with_name("revisions.json"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = audit(args.repo, json.loads(args.lock.read_text()))
        rendered = json.dumps(report, indent=2, ensure_ascii=True) + "\n"
        if args.output:
            args.output.write_text(rendered)
        else:
            sys.stdout.write(rendered)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Audit failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
