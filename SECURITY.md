# Security Policy

## Reporting a vulnerability

Do **not** open a public GitHub issue for security concerns. Instead,
email Apocky directly at `apocky13@gmail.com` with subject
`[CSLv3 SECURITY]`. Include:

- Affected component (parser / LSP / SMT / emit / etc.) + version
- Repro steps + minimal failing case
- Observed behavior + expected behavior
- Exploitation impact assessment (low / medium / high / critical)

## Scope

- Remote code execution or memory corruption in `parser.exe` or
  `cslv3-lsp.exe`.
- SMT-solver invocation that escapes the sandbox (arguments injection).
- Emit output that injects executable content (XSS in HTML target,
  macro-exec in LaTeX target, command-injection in any target).
- Audit-chain tampering that preserves signature verification.
- Proof-cache collision attacks that produce accepted false results.

Out of scope:

- Denial-of-service via pathological input to the parser (known
  non-goal ; parser is not hardened for adversarial input).
- LSP subprocess spawn behavior with attacker-controlled workspace paths
  (users opt in to trusting their workspace by opening files).
- Solver-side bugs in Z3 / CVC5 (report upstream).

## Response timeline

- Acknowledgment within 7 days.
- Initial triage within 14 days.
- Coordinated disclosure + fix within 90 days for confirmed issues.

## Supply-chain integrity

- Release artifacts ship with SHA-256 manifest + Ed25519 signature.
- The audit-chain in `.proof/chain.jsonl` records every SMT discharge
  and emit-sign operation. Chains are replay-verifiable via
  `parser.exe --smt-audit-verify`.
- CI matrix (see README.md) runs on every commit ; green gates are a
  precondition for release.

## PRIME_DIRECTIVE reminder

Per `PRIME_DIRECTIVE.md`, this project commits (as author-moral intent)
to refusing contributions that enable harm, control, manipulation,
surveillance, coercion, or weaponization. Vulnerabilities that could
facilitate those outcomes receive priority treatment regardless of
CVSS numeric score.

## Disclosure

After a fix ships, the vulnerability is documented in `CHANGELOG.md`
under the version's `Security` heading. Reporter credit is given
unless the reporter requests anonymity.
