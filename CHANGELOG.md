# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `keys` input: a map of master encryption keys created in the one vault, with the
  same attributes and defaults as `key`, and a `key_ids` output keyed like the map.
- Per-key `grant_services` and `grant_groups` (on `keys` entries and on `key`). When
  any key lists them, the module creates one `oci_identity_policy` with
  `use keys` / `use key-delegate` statements, each scoped to the keys' compartment and
  to that key's OCID. New inputs `create_grant_policy`, `grant_policy_compartment_id`
  and `grant_policy_name`; new outputs `grant_statements` and `grant_policy_id`.

### Changed

- The single `key` input is now managed as `keys["default"]`. A `moved` block maps
  `oci_kms_key.this[0]` to `oci_kms_key.this["default"]`, so existing keys are moved in
  state, not replaced. `key` and `key_id` keep working.

[Unreleased]: https://github.com/moveeeax/terraform-oci-key-management/compare/v1.1.0...HEAD
