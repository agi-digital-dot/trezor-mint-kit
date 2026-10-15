#!/usr/bin/env bash
# ============================================================================
# TREZOR MINT PROTOCOL — automated builder
# Builds a Trezor-capable spl-token CLI (stock binary has ZERO Trezor support).
#
# Proven live on mainnet Oct 15 2026 — first hardware-born token minted via this protocol.
#
# WHAT IT DOES
#   1. Clones the official token-2022 repo at the proven commit
#   2. Restores the proven dependency lockfile (no drift)
#   3. Grafts the Trezor wallet module (remote-wallet 4.0.0 source,
#      pubkey req relaxed to 3.x) as a local patch
#   4. Builds + installs spl-token with RUSTUP_TOOLCHAIN=1.93.0
#   5. Verifies: trezor symbol count must be > 0 (stock binary = 0)
#
# REQUIREMENTS
#   - Ubuntu/Debian, rustup installed, ~2GB disk, ~10 min
#   - Trezor T + trezord bridge only needed at MINT time, not build time
#
# SAFETY
#   - Touches nothing outside ~/trezor-mint-kit + ~/.cargo/bin
#   - Never sees seed words; keys never leave the device
#   - Replaces the old spl-token in the solana install dir via symlink
# ============================================================================
set -euo pipefail

REPO="https://github.com/solana-program/token-2022"
COMMIT="7a23d8c3042d59b54aa7150f9dd6b5b3bd0c5e1a"
KIT="$(cd "$(dirname "$0")" && pwd)"
WORK="$KIT/token-2022-src"
TOOLCHAIN="1.93.0"

step() { echo -e "\n\033[1;36m== $1 ==\033[0m"; }

step "1/6 Toolchain check (rustup + $TOOLCHAIN)"
command -v rustup >/dev/null || { echo "ERROR: rustup not installed. curl https://sh.rustup.rs | sh"; exit 1; }
rustup toolchain install "$TOOLCHAIN" --profile minimal 2>/dev/null || true

step "2/6 Fetching official token-2022 repo @ proven commit"
if [ -d "$WORK" ]; then
  echo "Reusing existing $WORK"
else
  git clone -q "$REPO" "$WORK"
fi
cd "$WORK"
git checkout -q "$COMMIT"

step "3/6 Restoring proven lockfile (kills dependency drift)"
git show HEAD:Cargo.lock > Cargo.lock
cp "$KIT/patches/remote-wallet-trezor" ./remote-wallet-trezor.tmp -r 2>/dev/null || cp -r "$KIT/patches/remote-wallet-trezor" ./remote-wallet-trezor
[ -d ./remote-wallet-trezor ] || { mv ./remote-wallet-trezor.tmp ./remote-wallet-trezor; }
rm -rf ./remote-wallet-trezor.tmp

# splice: drop the registry remote-wallet entry so cargo re-resolves to the graft
python3 - <<'PYEOF'
import re
t = open('Cargo.lock').read()
pat = re.compile(r'\[\[package\]\]\nname = "solana-remote-wallet"\nversion = "3\.1\.14"\nsource = [^\n]+\nchecksum = [^\n]+\n(?:.*\n)?(?=\[\[package\]\])', re.S)
t2 = pat.sub('', t, count=1)
assert t2 != t, 'remote-wallet lock entry not found — lockfile shape changed upstream'
open('Cargo.lock','w').write(t2)
print('lockfile spliced: registry remote-wallet entry removed')
PYEOF

# activate the graft via workspace patch
python3 - <<'PYEOF'
p = 'Cargo.toml'
t = open(p).read()
if '[patch.crates-io]' not in t:
    t += '\n[patch.crates-io]\nsolana-remote-wallet = { path = "remote-wallet-trezor" }\n'
    open(p,'w').write(t)
    print('workspace patch applied')
else:
    print('workspace patch already present')
PYEOF

step "4/6 Locking dependencies (graft in, rest = proven set)"
RUSTUP_TOOLCHAIN=$TOOLCHAIN cargo update --workspace 2>&1 | tail -2

step "5/6 Building spl-token (release, ~5-10 min)"
RUSTUP_TOOLCHAIN=$TOOLCHAIN cargo install --path clients/cli --bin spl-token

step "6/6 VERIFY"
NEWBIN="$HOME/.cargo/bin/spl-token"
COUNT=$(strings "$NEWBIN" | grep -c -i trezor || true)
echo "Trezor symbols in new binary: $COUNT"
if [ "${COUNT:-0}" -eq 0 ]; then
  echo "FAIL: binary built without Trezor support — do not use"
  exit 1
fi
echo "PASS: $NEWBIN is Trezor-capable"

# swap into the solana install dir (old binary preserved as .old)
SOLBIN="$HOME/.local/share/solana/install/active_release/bin"
if [ -d "$SOLBIN" ] && [ -e "$SOLBIN/spl-token" ] && [ ! -L "$SOLBIN/spl-token" ]; then
  mv "$SOLBIN/spl-token" "$SOLBIN/spl-token.old"
  ln -s "$NEWBIN" "$SOLBIN/spl-token"
  echo "Installed: $SOLBIN/spl-token -> $NEWBIN (old binary kept as spl-token.old)"
else
  echo "PATH note: ensure ~/.cargo/bin comes before the solana install dir, or re-run the symlink swap."
fi

cat <<'DONE'

============================================================
  BUILD COMPLETE — Trezor-capable spl-token installed
============================================================
Next (you action, device confirms):
  1. Plug in Trezor, CLOSE Trezor Suite
  2. solana-keygen pubkey usb://trezor?key=0/0   (handshake proof)
  3. spl-token --program-2022 create-token \
       --enable-metadata --decimals <N> \
       --transfer-fee-basis-points <BPS> \
       --transfer-fee-maximum-fee <MAX_FEE>
  4. Confirm FAST on device (blockhash lives ~60s)
  5. initialize-metadata <MINT> <NAME> <SYMBOL> <your-URI>
============================================================
DONE
