# API coverage audit

Google's discovery index lists v1 and v1beta3. On 2026-09-13,
`scripts/api/verify-discovery.py` confirmed exact equality of method metadata,
method/global parameters and schemas with Google revision 20260901: 42 v1
methods and 48 v1beta3 methods, with 324 schemas in each version.

Every row below is exercised by `everyMethodExecutesThroughCLIWithAllQueryParameters`
through CLI parsing, authentication injection and a mock HTTP transport, checking
method, complete path, query values/repetition and raw response preservation.
`everyDiscoveredRouteConstructsAndEnforcesCapabilities` additionally checks all
three capability selections for every method. These are offline contract tests;
they do not prove project-specific permissions or successful live processing.

Request bodies are accepted as complete raw JSON objects rather than a reduced
OCR option model. `constructsOCRRequestWithoutChangingBody` and workflow tests
verify preservation when submitting raw bodies and inserting local documents.
The offline discovery command exposes every request/response schema.

| Version | Method ID | HTTP | Capability |
| --- | --- | --- | --- |
| v1 | `documentai.operations.delete` | DELETE | deleter |
| v1 | `documentai.projects.locations.fetchProcessorTypes` | GET | reader |
| v1 | `documentai.projects.locations.get` | GET | reader |
| v1 | `documentai.projects.locations.list` | GET | reader |
| v1 | `documentai.projects.locations.operations.cancel` | POST | writer |
| v1 | `documentai.projects.locations.operations.get` | GET | reader |
| v1 | `documentai.projects.locations.operations.list` | GET | reader |
| v1 | `documentai.projects.locations.processorTypes.get` | GET | reader |
| v1 | `documentai.projects.locations.processorTypes.list` | GET | reader |
| v1 | `documentai.projects.locations.processors.batchProcess` | POST | writer |
| v1 | `documentai.projects.locations.processors.create` | POST | writer |
| v1 | `documentai.projects.locations.processors.delete` | DELETE | deleter |
| v1 | `documentai.projects.locations.processors.disable` | POST | writer |
| v1 | `documentai.projects.locations.processors.enable` | POST | writer |
| v1 | `documentai.projects.locations.processors.get` | GET | reader |
| v1 | `documentai.projects.locations.processors.humanReviewConfig.reviewDocument` | POST | writer |
| v1 | `documentai.projects.locations.processors.list` | GET | reader |
| v1 | `documentai.projects.locations.processors.process` | POST | writer |
| v1 | `documentai.projects.locations.processors.processorVersions.batchProcess` | POST | writer |
| v1 | `documentai.projects.locations.processors.processorVersions.delete` | DELETE | deleter |
| v1 | `documentai.projects.locations.processors.processorVersions.deploy` | POST | writer |
| v1 | `documentai.projects.locations.processors.processorVersions.evaluateProcessorVersion` | POST | writer |
| v1 | `documentai.projects.locations.processors.processorVersions.evaluations.get` | GET | reader |
| v1 | `documentai.projects.locations.processors.processorVersions.evaluations.list` | GET | reader |
| v1 | `documentai.projects.locations.processors.processorVersions.get` | GET | reader |
| v1 | `documentai.projects.locations.processors.processorVersions.list` | GET | reader |
| v1 | `documentai.projects.locations.processors.processorVersions.process` | POST | writer |
| v1 | `documentai.projects.locations.processors.processorVersions.train` | POST | writer |
| v1 | `documentai.projects.locations.processors.processorVersions.undeploy` | POST | writer |
| v1 | `documentai.projects.locations.processors.setDefaultProcessorVersion` | POST | writer |
| v1 | `documentai.projects.locations.schemas.create` | POST | writer |
| v1 | `documentai.projects.locations.schemas.delete` | DELETE | deleter |
| v1 | `documentai.projects.locations.schemas.get` | GET | reader |
| v1 | `documentai.projects.locations.schemas.list` | GET | reader |
| v1 | `documentai.projects.locations.schemas.patch` | PATCH | writer |
| v1 | `documentai.projects.locations.schemas.schemaVersions.create` | POST | writer |
| v1 | `documentai.projects.locations.schemas.schemaVersions.delete` | DELETE | deleter |
| v1 | `documentai.projects.locations.schemas.schemaVersions.generate` | POST | writer |
| v1 | `documentai.projects.locations.schemas.schemaVersions.get` | GET | reader |
| v1 | `documentai.projects.locations.schemas.schemaVersions.list` | GET | reader |
| v1 | `documentai.projects.locations.schemas.schemaVersions.patch` | PATCH | writer |
| v1 | `documentai.projects.operations.get` | GET | reader |
| v1beta3 | `documentai.projects.locations.fetchProcessorTypes` | GET | reader |
| v1beta3 | `documentai.projects.locations.get` | GET | reader |
| v1beta3 | `documentai.projects.locations.list` | GET | reader |
| v1beta3 | `documentai.projects.locations.operations.cancel` | POST | writer |
| v1beta3 | `documentai.projects.locations.operations.get` | GET | reader |
| v1beta3 | `documentai.projects.locations.operations.list` | GET | reader |
| v1beta3 | `documentai.projects.locations.processorTypes.get` | GET | reader |
| v1beta3 | `documentai.projects.locations.processorTypes.list` | GET | reader |
| v1beta3 | `documentai.projects.locations.processors.batchProcess` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.create` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.dataset.batchDeleteDocuments` | POST | deleter |
| v1beta3 | `documentai.projects.locations.processors.dataset.getDatasetSchema` | GET | reader |
| v1beta3 | `documentai.projects.locations.processors.dataset.getDocument` | GET | reader |
| v1beta3 | `documentai.projects.locations.processors.dataset.importDocuments` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.dataset.listDocuments` | POST | reader |
| v1beta3 | `documentai.projects.locations.processors.dataset.updateDatasetSchema` | PATCH | writer |
| v1beta3 | `documentai.projects.locations.processors.delete` | DELETE | deleter |
| v1beta3 | `documentai.projects.locations.processors.disable` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.enable` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.get` | GET | reader |
| v1beta3 | `documentai.projects.locations.processors.humanReviewConfig.reviewDocument` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.list` | GET | reader |
| v1beta3 | `documentai.projects.locations.processors.process` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.batchProcess` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.delete` | DELETE | deleter |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.deploy` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.evaluateProcessorVersion` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.evaluations.get` | GET | reader |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.evaluations.list` | GET | reader |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.get` | GET | reader |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.importProcessorVersion` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.list` | GET | reader |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.process` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.train` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.processorVersions.undeploy` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.setDefaultProcessorVersion` | POST | writer |
| v1beta3 | `documentai.projects.locations.processors.updateDataset` | PATCH | writer |
| v1beta3 | `documentai.projects.locations.schemas.create` | POST | writer |
| v1beta3 | `documentai.projects.locations.schemas.delete` | DELETE | deleter |
| v1beta3 | `documentai.projects.locations.schemas.get` | GET | reader |
| v1beta3 | `documentai.projects.locations.schemas.list` | GET | reader |
| v1beta3 | `documentai.projects.locations.schemas.patch` | PATCH | writer |
| v1beta3 | `documentai.projects.locations.schemas.schemaVersions.create` | POST | writer |
| v1beta3 | `documentai.projects.locations.schemas.schemaVersions.delete` | DELETE | deleter |
| v1beta3 | `documentai.projects.locations.schemas.schemaVersions.generate` | POST | writer |
| v1beta3 | `documentai.projects.locations.schemas.schemaVersions.get` | GET | reader |
| v1beta3 | `documentai.projects.locations.schemas.schemaVersions.list` | GET | reader |
| v1beta3 | `documentai.projects.locations.schemas.schemaVersions.patch` | PATCH | writer |

## Remaining verification

- Provider diagnostic redaction is covered through CLI integration, preserving
  useful permission/status information while removing credentials.
- Direct CLI file-body, polling and pagination integration tests now pass.
- Final release archives were rebuilt after the diagnostic and query fixes.
- Linux CI is configured but has not run locally (Docker daemon unavailable).
- Signed/notarized Cask publishing is optional release work, not performed.
- No live Google project fixtures or credentials were used.
