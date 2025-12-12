# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2025-12-12

### Added

- Selective Database Dumping: Introduced the ability to backup only specific databases by listing them in a databases.txt file.

- Automated Filtering: Added logic to dynamically generate exclusion arguments for pg_dumpall, ensuring global objects (roles, tablespaces) are preserved while skipping unwanted databases.

- Environment Variable Support: Integrated .env file support to manage remote host configurations (REMOTE_HOST, REMOTE_PGUSER, etc.) without hardcoding values in the Makefile.

- Advanced Restore Tuning: Added specialized PostgreSQL configurations (max_wal_size, synchronous_commit=off, fsync=off) to the local Docker container to significantly accelerate data restoration.

- Trigger Management: Implemented --disable-triggers support during the restoration process to bypass complex server-side constraints and validation logic during bulk data loads.

### Changed

- Optimized Backup Workflow: The dump target now intelligently switches between a full cluster dump (default) and a selective dump based on the presence of the databases.txt file.

- Resource Management: Enhanced Docker container lifecycle in the Makefile, ensuring stale containers are removed before starting a new initialization (docker-init).

- Fixed
Large Table Handling: Resolved issues where massive tables (e.g., GPS tracking logs) caused disk space exhaustion or connection timeouts by providing guidelines on using --exclude-table-data.

- EOF Errors: Fixed "unexpected end of file" errors during restore by optimizing I/O throughput and container memory allocation.