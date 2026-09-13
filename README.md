# google-document-ocr-gateway

Swift library and CLI for Google Document AI. The discovery-backed client exposes
all 42 v1 and 48 v1beta3 methods in Google's bundled revision 20260901, including
OCR processing options, batch processing, processor/version management,
evaluations, schemas, dataset management and long-running operation endpoints.

See the [completion audit](design-docs/specs/completion-audit.md) for verification
evidence and the limits of offline testing.

## CLI

```sh
swift build
swift run google-document-ocr-gateway --help
swift run google-document-ocr-gateway methods --api-version v1beta3
swift run google-document-ocr-gateway discovery --api-version v1

# Supply an access token through the environment, never as a command argument.
export GOOGLE_DOCUMENT_OCR_GATEWAY_ACCESS_TOKEN="$(gcloud auth print-access-token)"
swift run google-document-ocr-gateway reader projects.locations.processors.list \
  --location us --param parent=projects/PROJECT/locations/us

swift run google-document-ocr-gateway writer projects.locations.processors.process \
  --location us --param name=projects/PROJECT/locations/us/processors/PROCESSOR \
  --body request.json
```

`request.json` accepts the complete Google request schema, for example:

```json
{
  "rawDocument": {"content": "BASE64_DOCUMENT_BYTES", "mimeType": "application/pdf"},
  "processOptions": {"ocrConfig": {"enableNativePdfParsing": true, "enableImageQualityScores": true}}
}
```

Use `--api-version v1beta3` for beta methods. `--param NAME=VALUE` supplies any
path/query parameter from discovery, including `pageToken`, `pageSize`, `filter`
and `updateMask`; repeat it for repeated parameters. `--body -` reads JSON from
stdin. `--access-token-env NAME` selects another environment variable.

Reader accepts GET and dataset.listDocuments. Deleter accepts DELETE and
batchDeleteDocuments. Writer accepts remaining mutations. Requests reject
resource/endpoint region mismatches and redirects are not followed.

Calls emit `{"ok":true,"command":"...","data":...}`. Errors are JSON on stderr.
Exit codes: 1 unexpected/cancelled, 2 arguments, 3 credentials, 4 provider/transport.
Help/version are plain text; `discovery` returns the original discovery JSON.
Provider failures include HTTP status and scrubbed Google error details under
`error.provider`. Access tokens used for the request and sensitive credential or
document-content fields are redacted; successful JSON responses remain unchanged.

## Swift library

Add this package as a SwiftPM dependency and depend on its `AppCore` product:

```swift
import AppCore
import Foundation

let client = try DocumentAIClient(capability: .writer, location: "us")
let response = try await client.call(
  method: "projects.locations.processors.process",
  parameters: ["name": ["projects/PROJECT/locations/us/processors/PROCESSOR"]],
  body: Data(contentsOf: URL(fileURLWithPath: "request.json"))
)
```

Inject `DocumentAIHTTPTransport` and `DocumentAIAccessTokenProvider` for alternate
authentication and deterministic tests. `request` validates and constructs an
unauthenticated URLRequest without I/O. `DocumentAICatalog` exposes every method
and the complete offline discovery/schema document. Request and response bodies
are raw `Data`, preserving unknown fields and JSON numeric representations.

Run `swift test` and `mise exec -- swiftlint --quiet` for local verification.

## Local documents and pagination

```sh
google-document-ocr-gateway writer projects.locations.processors.process \
  --param name=projects/PROJECT/locations/us/processors/PROCESSOR \
  --file invoice.pdf --mime-type application/pdf

google-document-ocr-gateway reader projects.locations.processors.list \
  --param parent=projects/PROJECT/locations/us --all-pages
```

With `--file`, `--body` supplies additional processing options and must omit
`rawDocument`, `inlineDocument`, and `gcsDocument`. Swift callers use
`processDocument(name:content:mimeType:options:)` or `documentBody`.

`--all-pages` returns an array of complete response pages, preserving page-level
metadata. Swift callers use `allPages(method:parameters:body:maximumPages:)`.
Both query pagination and beta dataset body pagination are supported. An initial
page token is rejected; repeated tokens or exceeding the page limit fail instead
of returning an incomplete success. The default limit is 10,000 pages.

## Long-running operations

Add `--wait` to an operation-returning writer/deleter call, such as batchProcess,
train, deploy or delete. The mutation is submitted once. Polling returns the
complete terminal operation, including metadata and response. Without `--wait`,
the initial operation is returned immediately.

```sh
google-document-ocr-gateway writer projects.locations.processors.batchProcess \
  --param name=projects/PROJECT/locations/us/processors/PROCESSOR \
  --body batch.json --wait --timeout 600 --poll-interval 2

google-document-ocr-gateway reader projects.locations.operations.get \
  --param name=projects/PROJECT/locations/us/operations/OPERATION --wait
```

Swift callers use `callAndWait` on a writer/deleter or `waitForOperation` on a
reader with an existing operation JSON response. The polling timeout starts after
the initial call completes; it does not cancel the remote operation. Use the
operations.cancel method explicitly to request remote cancellation. Polling uses
a monotonic clock and bounds HTTP request timeouts by remaining polling time.
Custom injected transports must honor request timeouts and task cancellation.
Operation failure exits with code 5; polling timeout exits with code 6.
`--wait` cannot be combined with `--all-pages`.

## Service-account authentication

The library supports `DocumentAIServiceAccountTokenProvider(credentialJSON:)`.
The CLI accepts `--service-account-env NAME`, where the named environment variable
contains downloaded service-account JSON. It is mutually exclusive with
`--access-token-env`. No gcloud subprocess is required for this mode.

```sh
google-document-ocr-gateway reader projects.locations.processors.list \
  --param parent=projects/PROJECT/locations/us \
  --service-account-env GOOGLE_APPLICATION_CREDENTIALS_JSON
```

The provider signs an RS256 assertion for the cloud-platform scope, exchanges it
at Google's fixed token endpoint, and caches the access token with a 60-second
refresh margin. Transport, signer and clock are injectable. On macOS the default
signer uses `/usr/bin/openssl` with a temporary owner-only key file removed on
return. Token exchange errors omit provider text and credentials.

Existing Google Service Gateway user OAuth sessions can supply an access token
through the documented environment token mode. This package does not duplicate
the reference gateway's browser login and Keychain profile management.

Protocol reference: [Google service-account OAuth](https://developers.google.com/identity/protocols/oauth2/service-account).

## Installation verification

Run `python3 scripts/test-installed-cli.py .build/debug` after building. This
checks that a relocated binary, including invocation through a symlink, uses
its installed discovery resources. Ship the `google-document-ocr-gateway_AppCore.bundle`
next to the executable on macOS; the Homebrew archive and Cask staging scripts
include it. The formula keeps both under `libexec` and installs a launcher.
