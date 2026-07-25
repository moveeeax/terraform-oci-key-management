# terraform-oci-key-management

Terraform module that manages an [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/)
Key Management (KMS) vault and, optionally, a master encryption key inside it. Vaults hold
keys and secrets and expose the management and crypto endpoints used by other services.

## Usage

```hcl
module "key_management" {
  source = "github.com/moveeeax/terraform-oci-key-management"

  compartment_id = var.compartment_id
  display_name   = "prod-vault"
  vault_type     = "DEFAULT"

  key = {
    display_name = "prod-data-key"
    # algorithm defaults to AES and length defaults to AES-256; both are shown here
    # only to be explicit. length is in BYTES, not bits.
    algorithm = "AES"
    length    = 32

    # Optional: rotate automatically every 90 days. Rotation adds a key version and
    # leaves earlier versions usable for decryption.
    rotation_interval_in_days = 90
  }

  freeform_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Destroying is recoverable, but only for 30 days

Key material cannot be regenerated, so it is worth being precise about what a destroy does.

* `terraform destroy` does **not** purge anything immediately. The provider calls
  `ScheduleVaultDeletion` / `ScheduleKeyDeletion`, moving the resource to
  `PENDING_DELETION`.
* This module deliberately leaves `time_of_deletion` unset, so OCI applies its **maximum
  30-day** recovery window. The API would accept anything from 7 to 30 days.
* Within that window the deletion can be undone with
  `oci kms management vault cancel-deletion --vault-id <ocid>`, which also restores every
  key in the vault to its previous state.
* Once the window expires the vault and its key material are gone permanently and anything
  encrypted under those keys is unrecoverable.

Two things replace a key rather than update it, because `key_shape` and `protection_mode`
are immutable in the OCI API:

* changing `key.algorithm`, `key.length` or `key.curve_id`
* changing `key.protection_mode`

Terraform will report `must be replaced` for these. The replacement schedules the old key
for deletion on the same 30-day clock, so re-wrap any data still encrypted under it before
that window closes.

The module does not set [`prevent_destroy`](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#prevent_destroy)
on the vault or the key. That meta-argument only accepts a literal, so a module cannot
offer it as an option, and hard-coding it would make the module impossible to tear down in
non-production use. Guard production vaults with an OCI IAM policy that denies
`KEY_DELETE` / `VAULT_DELETE`, which no Terraform run can bypass.

## Key defaults

| Setting           | Default   | Why                                                                       |
|-------------------|-----------|---------------------------------------------------------------------------|
| `algorithm`       | `AES`     | Symmetric key suitable for envelope encryption of OCI service resources.  |
| `length`          | per algorithm | `AES` -> 32 bytes (AES-256), `RSA` -> 512 bytes (RSA-4096), `ECDSA` -> derived from `curve_id`. |
| `curve_id`        | `NIST_P521` for ECDSA, unset otherwise | Pinned explicitly so it always agrees with the derived length. |
| `protection_mode` | `HSM`     | Key material is created in and never leaves a FIPS 140-2 Level 3 HSM.     |
| rotation          | disabled  | Opt in with `rotation_interval_in_days` (60-365).                         |

`length` is in **bytes**. AES accepts 16/24/32, RSA accepts 256/384/512 and ECDSA accepts
32/48/66; a value that does not match the algorithm is rejected at plan time.

## Requirements

| Name      | Version         |
|-----------|-----------------|
| terraform | >= 1.5          |
| oci       | >= 5.0, < 9.0   |

The test suite under [`tests/`](tests) additionally needs Terraform >= 1.7 for
`mock_provider`; the module itself still works on 1.5.

## Inputs

| Name             | Description                                                       | Type          | Default     | Required |
|------------------|-------------------------------------------------------------------|---------------|-------------|:--------:|
| `compartment_id` | OCID of the compartment in which to create the vault.             | `string`      | n/a         |   yes    |
| `display_name`   | Human-readable name for the vault.                                | `string`      | n/a         |   yes    |
| `vault_type`     | Vault type (`DEFAULT` or `VIRTUAL_PRIVATE`).                      | `string`      | `"DEFAULT"` |    no    |
| `key`            | Optional master encryption key to create in the vault.            | `object(...)` | `null`      |    no    |
| `freeform_tags`  | Free-form tags applied to the vault and key.                      | `map(string)` | `{}`        |    no    |
| `defined_tags`   | Defined tags applied to the vault and key, keyed `namespace.key`. | `map(string)` | `{}`        |    no    |

### `key` object

| Attribute                   | Type     | Default          | Description                                                       |
|-----------------------------|----------|------------------|-------------------------------------------------------------------|
| `display_name`              | `string` | n/a (required)   | Name of the key.                                                  |
| `algorithm`                 | `string` | `"AES"`          | `AES`, `RSA` or `ECDSA`.                                          |
| `length`                    | `number` | per algorithm    | Key length in bytes. See the table above.                         |
| `curve_id`                  | `string` | `null`           | `NIST_P256`, `NIST_P384` or `NIST_P521`. ECDSA only.              |
| `protection_mode`           | `string` | `"HSM"`          | `HSM` or `SOFTWARE`.                                              |
| `rotation_interval_in_days` | `number` | `null`           | 60-365 to enable automatic rotation; `null` keeps rotation manual. |

## Outputs

| Name                  | Description                                       |
|-----------------------|---------------------------------------------------|
| `vault_id`            | OCID of the vault.                                |
| `management_endpoint` | Management endpoint of the vault.                 |
| `crypto_endpoint`     | Cryptographic endpoint of the vault.              |
| `key_id`              | OCID of the created key, if requested.            |
| `state`               | Lifecycle state of the vault.                     |

## Development

```sh
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform test          # mocked provider, no OCI credentials required
```

## License

[MIT](LICENSE)
