# Partner Lead Ingestion Pipeline

## 1. Overview

This project implements a partner lead ingestion pipeline using MuleSoft Anypoint Studio, Salesforce, and MySQL.

```text
Partner CSV
   |
   v
Member 1: File ingestion and validation
   |
   v
Queue / message hand-off
   |
   v
Member 2: Salesforce processing
   |
   v
Member 3: Database tracking (MySQL)
   |
   v
Member 4: Error handling and notifications

Member 5: Batch Status API and overall integration
```

The diagram shows team responsibilities, not necessarily the final execution order. Confirm the actual flow with the integration owner.

## 2. Team responsibilities

| Member | Responsibility | Main tasks |
|---|---|---|
| 1 | File ingestion | Receive CSV, validate filename/header/rows, detect duplicate files, register the batch before publishing messages, coordinate rejected-row tracking. |
| 2 | Salesforce processing | Connect to Salesforce, detect duplicates, create/update leads, save each record's outcome through the database operation. |
| 3 | Database and tracking | Maintain MySQL schema and reusable batch/record tracking operations. |
| 4 | Error handling and notifications | Coordinate error handling, retries, finalization, and notifications after processing. |
| 5 | API and overall integration | Build Batch Status API, integrate member flows, coordinate shared contracts, and run end-to-end tests. |

## 3. Suggested repository structure

Adapt folder names to the actual files contributed by the team. Preserve the internal structure of each MuleSoft project.

```text
partner-lead-ingestion-pipeline/
├── README.md
├── database/
│   └── partner_lead_db_schema.sql
├── member-1-file-ingestion/
│   └── (Member 1 MuleSoft project/files)
├── member-2-salesforce/
│   └── (Member 2 MuleSoft project/files)
├── member-3-database-tracking/
│   └── (Member 3 MuleSoft project/files)
└── member-5-api-integration/
    └── (Member 5 RAML/API and MuleSoft project/files)
```

Do not rename or move files inside a MuleSoft project unless the integration owner agrees. Preserve files such as `pom.xml`, `mule-artifact.json`, and the source/resource folders when present.

## 4. Member 3: database schema

- Database: `partner_lead_db`
- Development database: MySQL Server 8.4
- MuleSoft connection: Database Connector with a compatible MySQL JDBC driver

### `lead_batch`

Stores one row per registered input batch.

| Column | Purpose |
|---|---|
| `batch_id` | Primary key |
| `partner_id` | Partner identifier |
| `file_name` | Original input filename |
| `file_checksum` | Checksum used for duplicate-file detection |
| `record_count` | Expected number of records |
| `created_count` | Number created in Salesforce |
| `updated_count` | Number updated in Salesforce |
| `skipped_count` | Number of duplicates skipped |
| `rejected_count` | Number rejected |
| `failed_count` | Number failed |
| `batch_status` | Overall batch status |
| `correlation_id` | Batch trace identifier |
| `received_at` | Batch registration timestamp |
| `completed_at` | Batch completion timestamp |

Constraints: primary key `batch_id`; unique key (`file_name`, `file_checksum`).

### `lead_sync_status`

Stores individual record processing outcomes.

| Column | Purpose |
|---|---|
| `record_seq` | Auto-increment primary key |
| `batch_id` | Foreign key to `lead_batch.batch_id` |
| `row_number` | Source CSV row number |
| `lead_ref` | Partner lead reference |
| `email` | Lead email |
| `company` | Lead company |
| `salesforce_id` | Salesforce record ID, when available |
| `record_status` | Processing outcome |
| `error_code` | Error identifier, when applicable |
| `error_message` | Error description, when applicable |
| `retry_count` | Number of retries |
| `correlation_id` | Trace identifier |
| `processed_at` | Processing timestamp |

Constraints: primary key `record_seq`; foreign key `batch_id`; unique key (`batch_id`, `lead_ref`).

**Important actual schema details:**
- The database column is named `row_number`, not `source_row_number`.
- The MuleSoft input parameter used by `saveRecordOutcome` is `sourceRowNumber`; its SQL maps that parameter to the database column `row_number`.
- `lead_ref` is currently `NOT NULL`. A rejected row without a lead reference cannot be inserted into this table as currently defined. The team must agree whether to allow NULL or use an agreed placeholder before changing the schema.

## 5. Member 3: MuleSoft database operations

The `partner-lead-tracking-db` MuleSoft project contains these reusable subflows:

| Subflow | Purpose |
|---|---|
| `registerBatch` | Inserts a batch into `lead_batch` with initial status `RECEIVED`. |
| `saveRecordOutcome` | Inserts an individual record outcome into `lead_sync_status`. |
| `updateBatchSummary` | Recalculates counters and updates batch status and completion timestamp. |
| `getBatchById` | Retrieves batch-level information using `batchId`. |
| `getBatchRecords` | Retrieves record-level outcomes using `batchId`. |

### Expected inputs

**`registerBatch`**
- `vars.batchId`
- `vars.partnerId`
- `vars.fileName`
- `vars.fileChecksum`
- `vars.recordCount`
- `vars.correlationId`

The subflow sets `batchStatus` to `RECEIVED`.

**`saveRecordOutcome`**
- `vars.batchId`
- `vars.sourceRowNumber`
- `vars.leadRef`
- `vars.email`
- `vars.company`
- `vars.salesforceId`
- `vars.recordStatus`
- `vars.errorCode`
- `vars.errorMessage`
- `vars.retryCount`
- `vars.correlationId`

**`updateBatchSummary`, `getBatchById`, and `getBatchRecords`**
- `vars.batchId`

The Flow Reference caller must set the expected variables before invoking each subflow. Confirm exact names and data types with the database component owner.

## 6. Shared status values

Use these exact values consistently.

**Batch statuses**
- `RECEIVED`
- `PROCESSING`
- `COMPLETED`
- `COMPLETED_WITH_ERRORS`
- `REJECTED_FILE`
- `FAILED`

**Record statuses**
- `CREATED`
- `UPDATED`
- `DUPLICATE_SKIPPED`
- `REJECTED`
- `FAILED`

Do not introduce spelling variations without team agreement.

## 7. Integration decisions the team must confirm

1. **Batch registration:** Member 1 calls `registerBatch` before publishing records and supplies all required batch variables.
2. **Queue payload:** Agree on exact field names, types, and correlation ID propagation for every record message.
3. **Record outcome:** Member 2 calls `saveRecordOutcome` after Salesforce processing with the agreed values.
4. **Retry/idempotency:** `saveRecordOutcome` currently uses a normal INSERT. The unique key (`batch_id`, `lead_ref`) means inserting the same lead reference again in the same batch can cause a duplicate-key error. Agree whether retries should update/upsert the existing row or use another design. Do not silently remove the unique constraint.
5. **Missing lead reference:** Current `lead_ref NOT NULL` prevents recording a rejected row with no lead reference. Agree on nullable `lead_ref` versus an agreed placeholder before modifying the schema.
6. **Batch finalization:** Call `updateBatchSummary` only after all expected records have terminal outcomes. Confirm how `record_count` treats rejected rows.
7. **File rejection:** Agree how a rejected file is registered and how its status becomes `REJECTED_FILE`.
8. **API response:** Member 5 should use actual database column names and agree the response format for batch and record details.
9. **Database connection:** Each developer/environment configures its own connection details and credentials. Never commit passwords or secrets.

### Current summary calculation behavior

`updateBatchSummary` counts rows in `lead_sync_status` by `record_status`. It sets the batch to `PROCESSING` while the number of saved outcome rows is below `record_count`. Once the number reaches `record_count`, it sets `COMPLETED` or `COMPLETED_WITH_ERRORS` depending on whether any records are `REJECTED` or `FAILED`.

Verify this rule against the final handling of invalid rows, duplicate rows, retries, and file-level rejection before relying on it in production.

## 8. Local setup

### Prerequisites
- Anypoint Studio with a compatible Mule 4 runtime
- MySQL Server (development tested with MySQL 8.4)
- MySQL Workbench (optional)
- MuleSoft Database Connector
- Compatible MySQL JDBC driver

### Create the database
1. Open MySQL Workbench and connect to your local MySQL Server.
2. Open `database/partner_lead_db_schema.sql`.
3. Execute the script to create `partner_lead_db` and its tables.
4. Refresh Schemas and confirm `lead_batch` and `lead_sync_status` exist.

### Configure MuleSoft
1. Import the Member 3 MuleSoft project into Anypoint Studio.
2. Open the global database configuration `Database_Config`.
3. Configure your own JDBC URL, database name, username, password, and driver settings.
4. Keep credentials outside source control (for example, in local properties or secure configuration).
5. Confirm the application connects to `partner_lead_db`.

Never copy another developer's local password or commit credentials to GitHub.

## 9. Testing checklist

- [ ] MySQL schema creates both tables successfully.
- [ ] MuleSoft `Database_Config` connects successfully.
- [ ] `registerBatch` inserts a batch.
- [ ] `saveRecordOutcome` inserts a record outcome.
- [ ] `updateBatchSummary` updates counters and status as expected.
- [ ] `getBatchById` returns the expected batch.
- [ ] `getBatchRecords` returns the expected record outcomes.
- [ ] Duplicate-file behavior is tested.
- [ ] Duplicate-record and retry behavior is agreed and tested.
- [ ] Rejected rows with missing `lead_ref` are handled according to the agreed schema.
- [ ] Full CSV-to-Salesforce-to-database flow is tested end to end.
- [ ] Batch Status API returns expected batch and record information.
- [ ] Error handling and final notifications are tested.

The five database operations have passed basic local tests. This does not mean the complete multi-member pipeline has passed end-to-end testing.

## 10. GitHub collaboration guidelines

- Keep all members' work in this shared repository.
- Put each component in its agreed folder.
- Update this README when interfaces, schema, setup, or status values change.
- Coordinate before changing shared field names, database constraints, queue payloads, or status values.
- Use a separate branch and pull request for changes when the team adopts that workflow.
- Never upload passwords, access tokens, private keys, production data, or personal lead data.

GitHub browser uploads currently allow up to 100 files at once and a maximum of 25 MiB per file. Avoid uploading generated folders such as `target/`, logs, IDE workspace metadata, and unnecessary build output. Check files for secrets before uploading.

## 11. Member 3 hand-off status

- [x] MySQL database and two tables created.
- [x] MuleSoft database connection configured and tested locally.
- [x] Five reusable database subflows created.
- [x] Basic local tests completed for all five operations.
- [ ] Shared payload and variable names confirmed with Members 1 and 2.
- [ ] Retry/upsert behavior agreed.
- [ ] Missing `lead_ref` handling agreed.
- [ ] Full team end-to-end integration test completed.

**Member 3 component status:** ready for integration, subject to shared contract decisions and end-to-end testing.
