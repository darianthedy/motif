#!/usr/bin/env python3
"""Read and edit the games in Darian's Motif library, as Darian.

Signs in through Neon Auth with the account in ~/.config/caissa/motif.env
(MOTIF_EMAIL, MOTIF_PASSWORD) and uses Neon's Data API as that account, so
row-level security keeps it to Darian's own rows. The base URL comes from
motif/.env (VITE_NEON_BASE_URL).

Edits print a diff and change nothing unless --apply is given. Before writing,
the old PGN of every game it changes is saved under
~/.local/share/motif-db/backups/, and `restore <file>` puts them back.

    scripts/motif-db.py headers "London System" [--header Opening]
    scripts/motif-db.py set-header "London System" Opening "London System: Jobava" --game 3 [--apply]
    scripts/motif-db.py set-header "London System" Opening --from openings.json [--apply]
    scripts/motif-db.py set-header "London System" Opening "" --game 3 --apply   # removes the header
    scripts/motif-db.py restore ~/.local/share/motif-db/backups/<file>.json [--apply]

--from takes a JSON object of game position -> value: {"0": "...", "14": "..."}.
"""
import argparse
import http.cookiejar
import json
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

CREDS = Path.home() / ".config/caissa/motif.env"
MAIN_ENV = Path.home() / "Documents/projects/motif/.env"
BACKUPS = Path.home() / ".local/share/motif-db/backups"
ORIGIN = "http://localhost:5173"  # Neon Auth trusts localhost by default

HEADER = re.compile(r'^\[(\w+)\s+"((?:[^"\\]|\\.)*)"\]\s*$')


def read_env(path):
    env = {}
    for line in path.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env


class Motif:
    def __init__(self):
        env = Path(__file__).resolve().parent.parent / ".env"
        base = read_env(env if env.exists() else MAIN_ENV)["VITE_NEON_BASE_URL"].rstrip("/")
        m = re.match(r"(https://)([^.]+)\.(.*?)(/.*)", base)
        self.auth = f"{m[1]}{m[2]}.neonauth.{m[3]}{m[4]}/auth"
        self.rest = f"{m[1]}{m[2]}.apirest.{m[3]}{m[4]}/rest/v1"
        creds = read_env(CREDS)
        self.http = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self._call(f"{self.auth}/sign-in/email", "POST",
                   {"email": creds["MOTIF_EMAIL"], "password": creds["MOTIF_PASSWORD"]})
        r = self.http.open(urllib.request.Request(f"{self.auth}/get-session", headers={"Origin": ORIGIN}))
        self.jwt = r.headers["set-auth-jwt"]

    def _call(self, url, method="GET", body=None, headers=None):
        h = {"Origin": ORIGIN, "Content-Type": "application/json", **(headers or {})}
        data = json.dumps(body).encode() if body is not None else None
        text = self.http.open(urllib.request.Request(url, data, h, method=method)).read()
        return json.loads(text) if text else None

    def _rest(self, path, method="GET", body=None, headers=None):
        return self._call(f"{self.rest}/{path}", method, body,
                          {"Authorization": f"Bearer {self.jwt}", **(headers or {})})

    def select(self, table, **filters):
        rows, step = [], 1000
        q = {k: f"eq.{v}" for k, v in filters.items()}
        q["order"] = "id"
        while True:
            page = self._rest(f"{table}?{urllib.parse.urlencode(q)}",
                              headers={"Range": f"{len(rows)}-{len(rows) + step - 1}"})
            rows += page
            if len(page) < step:
                return rows

    def games(self, collection):
        cols = [c for c in self.select("game_collections") if c["name"] == collection]
        if not cols:
            names = sorted(c["name"] for c in self.select("game_collections"))
            sys.exit(f"no game collection named {collection!r}; have: {', '.join(names)}")
        if len(cols) > 1:
            sys.exit(f"{len(cols)} game collections are named {collection!r}; rename one first")
        return sorted(self.select("games", collection_id=cols[0]["id"]), key=lambda g: g["position"])

    def set_pgn(self, game_id, pgn):
        rows = self._rest(f"games?id=eq.{game_id}", "PATCH", {"pgn": pgn},
                          {"Prefer": "return=representation"})
        if len(rows) != 1 or rows[0]["pgn"] != pgn:
            raise RuntimeError(f"update of game {game_id} did not take")


def headers_of(pgn):
    out = {}
    for line in pgn.splitlines():
        m = HEADER.match(line)
        if m:
            out[m[1]] = m[2].replace('\\"', '"').replace("\\\\", "\\")
        elif line.strip():
            break
    return out


def with_header(pgn, name, value):
    """The PGN with header `name` set to `value`, or removed if value is empty."""
    lines = pgn.split("\n")
    end = 0  # index after the last header line
    found = None
    for i, line in enumerate(lines):
        m = HEADER.match(line)
        if m:
            end = i + 1
            if m[1] == name:
                found = i
        elif line.strip():
            break
    tag = f'[{name} "' + value.replace("\\", "\\\\").replace('"', '\\"') + '"]'
    if found is not None:
        if value:
            lines[found] = tag
        else:
            del lines[found]
    elif value:
        lines.insert(end, tag)
        if end == 0:
            lines.insert(1, "")
    return "\n".join(lines)


def label(g):
    h = headers_of(g["pgn"])
    return f"#{g['position']} {h.get('White', '?')} - {h.get('Black', '?')}"


def cmd_headers(m, args):
    for g in m.games(args.collection):
        h = headers_of(g["pgn"])
        if args.header:
            print(f"{label(g)}: {h.get(args.header, '(none)')!s}")
        else:
            print(f"{label(g)}: " + "; ".join(f"{k}={v}" for k, v in h.items()))


def write(m, changes, apply):
    """changes: [(game, new_pgn, description)]."""
    changes = [c for c in changes if c[1] != c[0]["pgn"]]
    for g, _, desc in changes:
        print(f"{label(g)}: {desc}")
    if not changes:
        print("nothing to change")
        return
    if not apply:
        print(f"\n{len(changes)} game(s) would change. Re-run with --apply to write.")
        return
    BACKUPS.mkdir(parents=True, exist_ok=True)
    backup = BACKUPS / f"{datetime.now():%Y%m%d-%H%M%S}.json"
    backup.write_text(json.dumps([{"id": g["id"], "position": g["position"], "pgn": g["pgn"]}
                                  for g, _, _ in changes], indent=1))
    print(f"\nbackup: {backup}")
    for g, pgn, _ in changes:
        m.set_pgn(g["id"], pgn)
    print(f"wrote {len(changes)} game(s)")


def cmd_set_header(m, args):
    if args.from_file:
        values = {int(k): v for k, v in json.loads(Path(args.from_file).read_text()).items()}
    elif args.value is not None and args.game:
        values = {p: args.value for p in args.game}
    else:
        sys.exit("give a value with --game N (repeatable), or --from file.json")
    games = {g["position"]: g for g in m.games(args.collection)}
    missing = sorted(set(values) - set(games))
    if missing:
        sys.exit(f"no game at position(s) {missing}")
    changes = []
    for pos, value in sorted(values.items()):
        g = games[pos]
        old = headers_of(g["pgn"]).get(args.header)
        new = with_header(g["pgn"], args.header, value)
        changes.append((g, new, f"{args.header}: {old!r} -> {value or None!r}"))
    write(m, changes, args.apply)


def cmd_restore(m, args):
    saved = json.loads(Path(args.file).read_text())
    current = {g["id"]: g for g in m.select("games")}
    gone = [s["id"] for s in saved if s["id"] not in current]
    if gone:
        print(f"skipping {len(gone)} game(s) no longer in the library")
    write(m, [(current[s["id"]], s["pgn"], "restore saved PGN") for s in saved if s["id"] in current],
          args.apply)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("headers")
    s.add_argument("collection")
    s.add_argument("--header")
    s = sub.add_parser("set-header")
    s.add_argument("collection")
    s.add_argument("header")
    s.add_argument("value", nargs="?")
    s.add_argument("--game", type=int, action="append", help="game position (repeatable)")
    s.add_argument("--from", dest="from_file")
    s.add_argument("--apply", action="store_true")
    s = sub.add_parser("restore")
    s.add_argument("file")
    s.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_]+", getattr(args, "header", None) or "x"):
        sys.exit("a header name is letters, digits and _ only")
    {"headers": cmd_headers, "set-header": cmd_set_header, "restore": cmd_restore}[args.cmd](Motif(), args)


if __name__ == "__main__":
    main()
