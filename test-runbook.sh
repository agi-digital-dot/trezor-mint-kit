#!/usr/bin/env bash
# TDI regression suite — encodes every bug caught live so it can't return.
# Run: bash test-runbook.sh   (read-only: CLI flag checks, HTTP 200s, on-chain params)
set -uo pipefail
PASS=0; FAIL=0
ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

BIN="${SPL_TOKEN:-$HOME/.cargo/bin/spl-token}"
MINT="3e2PYneVBXTyemNiSQ5VVkuYM4bYNPxLqvWkKjA5zXAM"
META="https://srv1537297.hstgr.cloud/tdi/token.json"
LOGO="https://srv1537297.hstgr.cloud/tdi/logo.png"

echo "== 1. CLI flags (bug: README shipped --recipient; CLI 5.6.1 wants --recipient-owner) =="
HELP=$("$BIN" mint --help 2>&1 || true)
echo "$HELP" | grep -q -- '--recipient-owner' && ok "mint supports --recipient-owner" || bad "mint lost --recipient-owner"
echo "$HELP" | grep -qE '^  --recipient \b' && bad "unexpected bare --recipient present" || ok "no bare --recipient"
AUTHHELP=$("$BIN" authorize --help 2>&1 || true)
echo "$AUTHHELP" | grep -q -- '--disable' && ok "authorize supports --disable" || bad "authorize lost --disable"

echo "== 2. Binary is the Trezor graft (stock = 0 trezor strings) =="
COUNT=$(strings "$BIN" | grep -c -i trezor || true)
[ "${COUNT:-0}" -gt 0 ] && ok "trezor symbols: $COUNT" || bad "binary lost Trezor support (count 0)"

echo "== 3. Metadata URLs live (bug class: placeholder URI / dead link) =="
J=$(curl -s --max-time 20 "$META")
echo "$J" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['name'] == 'True Digital Intelligence', d['name']
assert d['symbol'] == 'TDI'
assert d['image'] == '$LOGO'
assert 'PLACEHOLDER' not in json.dumps(d)
print('json-valid: name/symbol/image correct')
" && ok "token.json correct" || bad "token.json wrong/corrupt"
curl -sI --max-time 20 "$LOGO" | grep -qi 'content-type: image/png' && ok "logo.png is image/png" || bad "logo.png not serving as png"
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$LOGO")
[ "$CODE" = "200" ] && ok "logo 200" || bad "logo HTTP $CODE"
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://srv1537297.hstgr.cloud/tdi/")
[ "$CODE" != "200" ] && ok "dir listing blocked ($CODE)" || bad "dir listing open"

echo "== 4. On-chain params (locked values — alarm on ANY drift) =="
read -r SUPPLY DEC MINTAUTH FREEZE < <(curl -s --max-time 25 https://api.mainnet-beta.solana.com -X POST -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getAccountInfo\",\"params\":[\"$MINT\",{\"encoding\":\"jsonParsed\"}]}" \
  | python3 -c "
import sys, json
i = json.load(sys.stdin)['result']['value']['data']['parsed']['info']
print(int(i['supply'])/10**6, i['decimals'], i.get('mintAuthority') or 'None', i.get('freezeAuthority') or 'None')")
[ "$SUPPLY" = "333333.0" ] && ok "supply 333,333 final" || bad "supply drifted: $SUPPLY"
[ "$DEC" = "6" ] && ok "decimals 6" || bad "decimals drifted: $DEC"
[ "$MINTAUTH" = "None" ] && ok "mint authority renounced" || bad "MINT AUTHORITY CHANGED: $MINTAUTH"
[ "$FREEZE" = "None" ] && ok "freeze authority absent" || bad "freeze authority appeared: $FREEZE"

echo
echo "== 5. Public proof pack (bug class: dead screenshot URLs / non-runnable proof) =="
[ -x "$HOME/tdi-provenance/proof.sh" ] && ok "proof.sh is executable" || bad "proof.sh lost exec bit"
for f in 01-supply 02-device-key 03-authority-match 04-five-year-gap 05-binary-proof 06-genesis 07-solscan; do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://raw.githubusercontent.com/agi-digital-dot/tdi-true-digital/main/screenshots/$f.png")
  [ "$CODE" = "200" ] && ok "$f.png live" || bad "$f.png HTTP $CODE"
done

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
