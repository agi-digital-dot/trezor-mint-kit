# TREZOR MINT KIT — hardware-born Solana tokens

**The first documented, mainnet-proven way to create a Solana Token-2022 token signed entirely by a Trezor.**
First token born on hardware via this protocol: Oct 15 2026 — mint `3e2PYneVBXTyemNiSQ5VVkuYM4bYNPxLqvWkKjA5zXAM` (Solscan-verifiable).

## Why this kit exists

The stock `spl-token` binary (5.6.1) is built against `solana-remote-wallet 3.1.x`, a library version with the **Trezor code deleted**. Any `usb://trezor` path fails with `not a manufacturer`. Upstream ships no fix (the 4.x library that restored Trezor is incompatible with the CLI's dependency train). This kit grafts the Trezor module back in — no forks, no vendoring, reproducible.

## What's inside

```
trezor-mint-kit/
├── README.md                     ← this file
├── build.sh                      ← one-shot automated builder (bash + python3 only)
├── patches/
│   └── remote-wallet-trezor/     ← the graft: remote-wallet 4.0.0 source,
│                                    pubkey req relaxed to 3.x, version aligned 3.1.14
└── VC-BRIEF.md                   ← 3-page sellable workflow brief
```

## Quick start

```bash
cd trezor-mint-kit
chmod +x build.sh
./build.sh
```

- Takes ~10 min (clone + rust toolchain + release build)
- Verifies itself: **fails loudly if the built binary has 0 Trezor symbols**
- Installs to `~/.cargo/bin/spl-token` and symlinks it over the solana install dir copy (old binary saved as `spl-token.old`)

Requirements: Ubuntu/Debian, `rustup`, `git`, `python3`, `strings` (binutils). Trezor not needed until mint time.

## Mint ceremony (you action everything; keys never leave the device)

```bash
# 0. Plug Trezor T in, CLOSE Trezor Suite (it hogs the USB session)
# 1. Handshake proof (prints your Trezor's Solana address):
solana-keygen pubkey usb://trezor?key=0/0

# 2. Confirm your config (payer + mainnet):
solana config get    # RPC: mainnet-beta · Keypair Path: usb://trezor?key=0/0

# 3. CREATE — no positional arg! The mint keypair is generated fresh;
#    the Trezor (config payer) signs + pays rent (~0.05 SOL):
spl-token --program-2022 create-token \
  --enable-metadata \
  --decimals 6 \
  --transfer-fee-basis-points <BPS> \
  --transfer-fee-maximum-fee <MAX_FEE>   # example: 100 bps = 1% fee on transfers

# 4. Name it (URI = your hosted metadata JSON):
spl-token initialize-metadata <MINT> <NAME> <SYMBOL> <YOUR_URI>

# 5. Mint supply to the Trezor address:
spl-token mint <MINT> <SUPPLY>

# 6. Verify on solscan.io: supply = your amount · mint/freeze authority = Trezor address

# 7. Renounce (each confirmed on-device):
spl-token authorize <MINT> mint --disable
spl-token authorize <MINT> freeze --disable
# metadata update authority: disable via initialize-metadata update flow
# KEEP withdraw-withheld authority (fee collection) — move to Ledger later if desired
```

## Failure playbook (all hit live, all solved)

| Error | Meaning | Fix |
|---|---|---|
| `not a manufacturer` | Binary lacks Trezor code | Run `build.sh` |
| `BlockhashNotFound` | Device confirm took >60s; tx **may still have landed** | Check the mint account on RPC/Solscan BEFORE retrying |
| `account already in use` | A positional arg collided with an existing account | Don't pass a positional to `create-token`; payer comes from config |
| `protocol error: Unknown error` | Trezor Suite open / bridge hiccup | Close Suite, replug, retry `solana-keygen pubkey` |

## Phase C — name it, mint supply, verify (mainnet, Trezor signs)

> One step per command. Trezor confirms each on its screen. Mint: `3e2PYneVBXTyemNiSQ5VVkuYM4bYNPxLqvWkKjA5zXAM`

```bash
# C1. Name it (URI = your hosted metadata JSON — see metadata/token.json)
spl-token initialize-metadata 3e2PYneVBXTyemNiSQ5VVkuYM4bYNPxLqvWkKjA5zXAM "TDI" "TDI" <YOUR_URI>

# C2. Mint the full supply to your Trezor address
spl-token mint 3e2PYneVBXTyemNiSQ5VVkuYM4bYNPxLqvWkKjA5zXAM 333333 --recipient DbJ5opgLXjpHkB4STqiJqJMvnVfhE8Pas4aKymzZPe7W

# C3. Prove it (read-only, no signature)
spl-token supply 3e2PYneVBXTyemNiSQ5VVkuYM4bYNPxLqvWkKjA5zXAM
# expect: 333333
solana-keygen pubkey usb://trezor?key=0/0
# expect: DbJ5opgLXjpHkB4STqiJqJMvnVfhE8Pas4aKymzZPe7W
```

### Fee-cap note (audit finding, Oct 15)
On-chain `maximumFee` = 6,433,326,900,000,000 raw = **6,433,326.9 TDI** — the create command's
`--transfer-fee-maximum-fee` value was parsed as a UI amount and ×10^6 by decimals. Impact: none at
193 bps (the cap only binds above 3.33M TDI transferred in one tx — more than the entire supply),
fee charged is always exactly 1.93%. Fix if you want it exact, one Trezor-signed command:

```bash
spl-token set-transfer-fee 3e2PYneVBXTyemNiSQ5VVkuYM4bYNPxLqvWkKjA5zXAM 193 6433326900000000
```
(the raw-integer form — same numbers the RPC now shows — re-signs the cap at the on-chain truth).

## Provenance

- Upstream repo: `solana-program/token-2022` @ `7a23d8c3` (Oct 2026)
- Graft source: `solana-remote-wallet 4.0.0` (crates.io), trezor-client 0.1.5 linked
- Lockfile: upstream's own shipped lock minus the registry remote-wallet entry — everything else stays on the proven published set
- Build toolchain: Rust 1.93.0 (repo's pinned channel)
- Verification gate: `strings ~/.cargo/bin/spl-token | grep -c -i trezor` → **219** (stock: 0)

## Security notes

- Kit never touches seed words, keys, or signing — the Trezor screen is the only trust surface
- Build is fully offline-capable after the initial clone/crates fetch
- The graft only relaxes a version requirement (`solana-pubkey ~4.1.0 → 3.0.0`); no crypto code was modified. Audit diff: `diff -r patches/remote-wallet-trezor/src <(crates.io 4.0.0 sources)` — only `Cargo.toml` differs.

---
*Protocol by Robert Shields Jr. McDougall + ECHO Master Control — Oct 15 2026.*
