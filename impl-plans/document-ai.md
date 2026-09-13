# Implementation and completion audit

- [x] Inspect scaffold and reference gateway design.
- [x] Obtain authoritative discovery snapshots for v1 and v1beta3.
- [x] Implement discoverable complete method catalog and schema access.
- [x] Implement authenticated async requests with capability enforcement.
- [x] Expose all operations and request fields through CLI and library.
- [x] Add OCR file helpers and pagination to library and CLI.
- [x] Add long-running operation workflows.
- [x] Verify credential handling, regional routing and error contract.
- [x] Test every discovery method's request construction and capability boundary.
- [x] Document SDK examples and CLI workflows; align packaging and CI.
- [x] Run complete tests, lint, CLI smoke checks and requirement-by-requirement audit.

Live provider tests must use explicitly configured credentials and fixtures;
offline transport tests must cover the complete surface independently of access
to a billed Google Cloud project. Record live verification limitations honestly.

## Current evidence

The CLI lists 42 v1 and 48 v1beta3 methods. Offline tests cover each method's
route construction and all three capability boundaries, OCR body preservation,
region/path rejection, query encoding and authenticated mock transport.
No live provider call has been made. Provider errors now include scrubbed Google error details with HTTP status. The resource bundle is now included by both archive and Cask staging.

Pagination and local OCR helpers are verified with mock transports, including
POST body pagination, opaque query tokens, cycle detection, conflicting document
sources and preservation of large JSON number lexemes. Suite: 13 passing tests.

Operation workflows submit once, poll by exact returned name, preserve terminal
JSON and distinguish terminal provider failure from polling timeout. Mock tests
cover those behaviors and rejection of invalid timing/non-operation mutations.

Service-account authentication now supports injectable signing/transport/time,
fixed Google token endpoint validation, cached OAuth exchange and CLI environment
JSON selection. Existing gateway user OAuth tokens work via the environment token
provider. No credential values were inspected or live token exchanges performed.

Installation audit found and fixed missing Cask resource staging and SwiftPM's
symlink lookup fallback. `scripts/test-installed-cli.py` relocates the binary and
resources, exercises both API versions directly and via symlink, then modifies
only a temporary discovery copy to prove that installed resources are loaded.
Debug relocation and symlink checks pass. macOS CI now runs tests, lint and this
installation check. Existing Linux CI now runs tests as well as a release build;
FoundationNetworking and libc imports are conditional for that existing target.

Both macOS release archives now build (darwin-arm64 and darwin-x64). The
installation/symlink resource probe passes for both release binaries, including
Intel execution on this host. Formula rendering and `ruby -c` pass. Cask dry-run
and shell syntax validation pass; signing/notarization were not performed.
Local Linux execution is unverified because Docker's daemon socket is unavailable.

Current discovery parity and per-method SDK/CLI evidence are recorded in
`design-docs/specs/api-coverage.md`. All 90 methods now execute through the CLI
with mock transport and all method query parameters, including repeated values.
Wire query encoding now escapes literal plus signs to preserve opaque tokens.

Direct CLI integration tests now cover file OCR with options, pagination,
operation polling, credential-redacted provider diagnostics and malformed OCR
options. All implementation items are complete; final current-state release
rebuild and completion audit remain.

Final verification: 27 tests pass; strict SwiftLint passes; both macOS release
archives rebuilt from final Swift sources and relocated resource probes pass.
See `design-docs/specs/completion-audit.md` for the requirement-by-requirement
audit and explicit live-provider, Linux and notarization verification limits.
