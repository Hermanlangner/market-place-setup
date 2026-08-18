#!/usr/bin/env python3
"""Vendor third-party plugins with provenance and update detection.

Each vendored plugin lives at plugins/vendored/<name>/ with a vendor.json
recording upstream, pinned ref/sha, and vetted status. See
docs/automation.md for the full pipeline (detect -> scan -> audit -> PR).

Commands:
  add <git-url> <name> [--path SUBDIR] [--ref REF]  vendor a plugin
  check                                             exit 1 + print UPDATE lines if upstream moved
  update <name>                                     pull latest upstream, reset vetted to false
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VENDOR_DIR = ROOT / "plugins" / "vendored"


def sh(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def latest_upstream(url):
    """Highest semver tag (tag, sha), else (None, HEAD sha)."""
    tags = []
    for line in sh("git", "ls-remote", "--tags", "--refs", url).splitlines():
        sha, _, ref = line.partition("\t")
        tag = ref.removeprefix("refs/tags/")
        m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", tag)
        if m:
            tags.append((tuple(map(int, m.groups())), tag, sha))
    if tags:
        _, tag, sha = max(tags)
        return tag, sha
    return None, sh("git", "ls-remote", url, "HEAD").split()[0]


def clone_at(url, ref, dest):
    args = ["git", "clone", "--quiet", "--depth", "1"]
    if ref:
        args += ["--branch", ref]
    subprocess.run(args + [url, str(dest)], check=True, capture_output=True, text=True)
    return sh("git", "rev-parse", "HEAD", cwd=dest)


def copy_tree(src, dest):
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest, ignore=shutil.ignore_patterns(".git"))


def vendored():
    for vj in sorted(VENDOR_DIR.glob("*/vendor.json")):
        yield vj.parent.name, json.loads(vj.read_text()), vj


def write_meta(dest, meta):
    (dest / "vendor.json").write_text(json.dumps(meta, indent=2) + "\n")


def cmd_add(a):
    dest = VENDOR_DIR / a.name
    if dest.exists():
        sys.exit(f"{dest} already exists — use `update`")
    ref = a.ref or latest_upstream(a.url)[0]
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td) / "src"
        sha = clone_at(a.url, ref, tmp)
        copy_tree(tmp / a.path if a.path != "." else tmp, dest)
    write_meta(dest, {"upstream": a.url, "path": a.path, "ref": ref, "sha": sha, "vetted": False})
    print(f"vendored {a.name} @ {ref or 'HEAD'} ({sha[:12]})")
    print('next: scan + audit it, set "vetted": true, add a marketplace entry')


def cmd_check(_):
    updates = 0
    for name, meta, _ in vendored():
        tag, sha = latest_upstream(meta["upstream"])
        current = meta.get("ref") or meta["sha"][:12]
        if (tag and tag != meta.get("ref")) or (not tag and sha != meta["sha"]):
            print(f"UPDATE {name}: {current} -> {tag or sha[:12]}")
            updates += 1
        else:
            print(f"ok     {name}: {current}")
    sys.exit(1 if updates else 0)


def cmd_update(a):
    for name, meta, vj in vendored():
        if name != a.name:
            continue
        tag, _ = latest_upstream(meta["upstream"])
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td) / "src"
            sha = clone_at(meta["upstream"], tag, tmp)
            copy_tree(tmp / meta["path"] if meta["path"] != "." else tmp, vj.parent)
        meta.update(ref=tag, sha=sha, vetted=False)
        write_meta(vj.parent, meta)
        print(f"updated {name} -> {tag or sha[:12]} — vetted reset to false, review before merge")
        return
    sys.exit(f"no vendored plugin named {a.name}")


p = argparse.ArgumentParser(description=__doc__)
sub = p.add_subparsers(required=True)
pa = sub.add_parser("add")
pa.add_argument("url")
pa.add_argument("name")
pa.add_argument("--path", default=".")
pa.add_argument("--ref")
pa.set_defaults(fn=cmd_add)
sub.add_parser("check").set_defaults(fn=cmd_check)
pu = sub.add_parser("update")
pu.add_argument("name")
pu.set_defaults(fn=cmd_update)
args = p.parse_args()
args.fn(args)
