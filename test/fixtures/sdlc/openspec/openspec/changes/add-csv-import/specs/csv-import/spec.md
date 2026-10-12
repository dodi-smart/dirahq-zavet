## ADDED Requirements

### Requirement: CSV upload
The system SHALL accept a CSV file of at most 10 MB.

#### Scenario: Valid file
- **WHEN** an operator uploads a well-formed CSV
- **THEN** every row is imported

#### Scenario: Oversize file
- **WHEN** the file exceeds 10 MB
- **THEN** the upload is rejected

### Requirement: Row validation
The system SHALL reject rows with a missing id.

#### Scenario: Missing id
- **WHEN** a row has no id
- **THEN** it is reported and skipped

## MODIFIED Requirements

### Requirement: Import size limit
The system SHALL cap an import at 10 000 rows.

#### Scenario: Row cap
- **WHEN** the file has more rows
- **THEN** the import stops at the cap

## REMOVED Requirements

### Requirement: Manual row entry
**Reason**: Replaced by upload.
**Migration**: Use the CSV upload.
