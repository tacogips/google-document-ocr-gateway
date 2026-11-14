# Document AI SDK and CLI

The objective is full Document AI functionality from Swift and CLI, following
`google-service-gateway`: capability boundaries, injected async HTTP transport and
credentials, stable JSON envelopes, no credential persistence, pagination and
long-running operation support.

Coverage is defined by Google's REST discovery documents for v1 and v1beta3,
vendored under Sources/AppCore/Resources (revision 20260901). Every discovered
method must be callable with all documented query parameters and arbitrary JSON
request bodies, preserving OCR options and future fields. Responses remain raw
JSON bytes to preserve numeric values and unknown fields. The complete schemas
are available offline. No hand-selected OCR-only subset defines completion.

Reader permits reads, including dataset.listDocuments (a POST read). Deleter
owns DELETE and batchDeleteDocuments. Writer owns other mutations. API versions
are explicit; regional endpoints are selected explicitly and checked against
resource locations before credentials are sent. Tokens come from an injected
provider or a named environment variable.

The existing AppCore target remains the library boundary. Specialized clients,
CLI aliases, local-file OCR helpers, pagination, operation polling and credential
integration should layer on the common discovery-backed request implementation.

Sources:
- https://documentai.googleapis.com/$discovery/rest?version=v1
- https://documentai.googleapis.com/$discovery/rest?version=v1beta3
- https://docs.cloud.google.com/document-ai/docs/reference/rest
