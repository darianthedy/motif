#!/usr/bin/env bash
#
# Can a native iOS client sign in to Neon Auth and read the Data API?
#
# Calls the same endpoints a Swift app would, the way URLSession would: a
# cookie jar (HTTPCookieStorage) and no Origin header. Prints statuses and
# which headers came back, never a token or the password.
#
#   scripts/ios-auth-spike.sh you@example.com

set -euo pipefail
cd "$(dirname "$0")/.."

email="${1:?usage: $0 <email>}"
[ -t 0 ] || { echo "Needs a terminal to ask for the password — run it in your own shell, not via '!'." >&2; exit 1; }
read -rsp "Password for $email: " password; echo

set -a; . ./.env; set +a
base="${VITE_NEON_BASE_URL:?VITE_NEON_BASE_URL is not set in .env}"
# The same derivation as @neondatabase/neon-js: insert a label after the first
# hostname label.
derive() { node -e 'const u=new URL(process.argv[1]);u.hostname=u.hostname.replace(/^([^.]+)\./,`$1.${process.argv[2]}.`);console.log(u.origin+u.pathname)' "$base" "$1"; }
auth="$(derive neonauth)/auth"
rest="$(derive apirest)/rest/v1"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
jar="$work/cookies"

# $1 name, rest = curl args. Leaves headers in $work/h, body in $work/b.
call() {
  local name="$1"; shift
  local status
  status=$(curl -s -o "$work/b" -D "$work/h" -w '%{http_code}' -b "$jar" -c "$jar" "$@")
  echo "== $name: HTTP $status"
  grep -iE '^(set-auth-jwt|set-auth-token|set-cookie):' "$work/h" | sed -E 's/:.*/: (present)/I' | sort -u || true
}
# An absent header is an answer, not an error.
header() { { grep -i "^$1:" "$work/h" || true; } | head -1 | cut -d' ' -f2- | tr -d '\r'; }

body=$(EMAIL="$email" PASSWORD="$password" node -e 'console.log(JSON.stringify({email:process.env.EMAIL,password:process.env.PASSWORD}))')
call "sign-in (no Origin)" -X POST "$auth/sign-in/email" -H 'Content-Type: application/json' -d "$body"
bearer=$(header set-auth-token)

call "get-session via cookie" "$auth/get-session"
jwt=$(header set-auth-jwt)
node -e 'const b=require("fs").readFileSync(process.argv[1],"utf8");try{const j=JSON.parse(b);console.log("   user:",j?.user?.id?"(present)":"none")}catch{console.log("   body not JSON")}' "$work/b"

call "token via cookie" "$auth/token"
[ -n "$jwt" ] || jwt=$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).token??"")}catch{}' "$work/b")

if [ -n "$bearer" ]; then
  rm -f "$jar"
  call "get-session via bearer (no cookies)" "$auth/get-session" -H "Authorization: Bearer $bearer"
fi

if [ -z "$jwt" ]; then echo "!! no JWT obtained — Data API not tried"; exit 1; fi
echo "== JWT obtained (length ${#jwt})"
call "Data API select collections" "$rest/collections?select=id&limit=1" -H "Authorization: Bearer $jwt"
node -e 'const b=require("fs").readFileSync(process.argv[1],"utf8");try{const j=JSON.parse(b);console.log("   rows:",Array.isArray(j)?j.length:JSON.stringify(j).slice(0,200))}catch{console.log("   ",b.slice(0,200))}' "$work/b"
