# Architecture

SwiftPM targets remain `AppCore` (public library), `AppCLI` (async entry point)
and `AppCoreTests`. `DocumentAICatalog` loads versioned discovery metadata and
schemas from bundled resources. `DocumentAIClient` constructs validated requests,
enforces the selected reader/writer/deleter capability and executes requests
through injected token and HTTP transport protocols. `DocumentAICLI` maps explicit
commands to the same public client and writes stable JSON envelopes.

See [Document AI design](document-ai.md) for scope and the
[implementation plan](../../impl-plans/document-ai.md) for outstanding work.
