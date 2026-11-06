# terraform-oci-key-management

Terraform module that manages an [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/)
Key Management (KMS) vault, any number of master encryption keys inside it, and optionally the
IAM policy that lets OCI services and groups use those keys. Vaults hold keys and secrets and
expose the management and crypto endpoints used by other services.

## Usage

```hcl
module "key_management" {
  source = "github.com/moveeeax/terraform-oci-key-management?ref=v1.2.0"

  compartment_id = var.compartment_id
  display_name   = "prod-vault"
  vault_type     = "DEFAULT"

  keys = {
    volumes = {
      display_name = "prod-volumes-key"
      # algorithm defaults to AES and length defaults to AES-256; both are shown here
      # only to be explicit. length is in BYTES, not bits.
      algorithm = "AES"
      length    = 32

      # Optional: rotate automatically every 90 days. Rotation adds a key version and
      # leaves earlier versions usable for decryption.
      rotation_interval_in_days = 90

      # Optional: let Block Volume and OKE use the key, and let a group attach it.
      grant_services = ["blockstorage", "oke"]
      grant_groups   = ["VolumeAdmins"]
    }

    buckets = {
      display_name   = "prod-buckets-key"
      grant_services = ["objectstorage-eu-frankfurt-1"]
    }
  }

  freeform_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

The older single-key form, `key = { display_name = "..." }`, still works. That key is
managed as `keys["default"]`: `key_id` and `key_ids["default"]` both return it, and a
`moved` block carries an existing `oci_kms_key.this[0]` from v1.1.x and earlier to
`oci_kms_key.this["default"]` without replacing it. `keys` cannot hold a `default` entry
while `key` is set. To switch to `keys`, rename `key = {...}` to `keys = { default = {...} }`;
the address stays the same and nothing is replaced.

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

* changing `algorithm`, `length` or `curve_id` of a key
* changing `protection_mode` of a key
* renaming the key's entry in `keys`

Terraform will report `must be replaced` for these. The replacement schedules the old key
for deletion on the same 30-day clock, so re-wrap any data still encrypted under it before
that window closes.

The module does not set [`prevent_destroy`](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#prevent_destroy)
on the vault or the key. That meta-argument only accepts a literal, so a module cannot
offer it as an option, and hard-coding it would make the module impossible to tear down in
non-production use. Guard production vaults with an OCI IAM policy that denies
`KEY_DELETE` / `VAULT_DELETE`, which no Terraform run can bypass.

## Letting services use the keys

OCI services refuse a customer-managed key until IAM lets them use it, and the error is an
opaque authorization failure. List the services on the key with `grant_services` and the
groups that attach the key to resources with `grant_groups`, and the module creates one
`oci_identity_policy` with these statements, from the OCI
[Common Policies](https://docs.oracle.com/en-us/iaas/Content/Identity/Concepts/commonpolicies.htm)
page:

```text
Allow service blockstorage, oke to use keys in compartment id <compartment_id> where target.key.id = '<key OCID>'
Allow group VolumeAdmins to use key-delegate in compartment id <compartment_id> where target.key.id = '<key OCID>'
```

Each statement is limited to one key and to the vault's compartment. `key-delegate` lets a
group associate the key with a bucket, volume, cluster or stream pool without using the key
itself. Object Storage is regional, so its service name carries the region:
`objectstorage-<region identifier>`, one entry per region. Other names from that page are
`blockstorage`, `oke` and `streaming`; the module checks the format of a name, not whether
OCI knows it.

* The policy goes into `compartment_id` unless `grant_policy_compartment_id` says otherwise
  (the tenancy OCID, for example). Its name is `<display_name>-key-grants` unless
  `grant_policy_name` is set. Policy names are unique in the tenancy.
* OCI accepts IAM writes only in the tenancy's home region. If the provider points at
  another region, set `create_grant_policy = false` and attach the `grant_statements`
  output with a home-region provider yourself.
* Groups outside the Default identity domain are written `'Domain'/'Group'`.

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
| oci       | >= 5.0, < 10.0  |

The test suite under [`tests/`](tests) additionally needs Terraform >= 1.7 for
`mock_provider`; the module itself still works on 1.5.

## Inputs

| Name             | Description                                                       | Type          | Default     | Required |
|------------------|-------------------------------------------------------------------|---------------|-------------|:--------:|
| `compartment_id` | OCID of the compartment in which to create the vault.             | `string`      | n/a         |   yes    |
| `display_name`   | Human-readable name for the vault.                                | `string`      | n/a         |   yes    |
| `vault_type`     | Vault type (`DEFAULT` or `VIRTUAL_PRIVATE`).                      | `string`      | `"DEFAULT"` |    no    |
| `keys`           | Keys to create in the vault, keyed by a stable name.              | `map(object(...))` | `{}`   |    no    |
| `key`            | Single key, kept for compatibility; managed as `keys["default"]`. | `object(...)` | `null`      |    no    |
| `create_grant_policy` | Create the IAM policy for `grant_services` / `grant_groups`. | `bool`        | `true`      |    no    |
| `grant_policy_compartment_id` | Compartment or tenancy for the grant policy; null means `compartment_id`. | `string` | `null` | no |
| `grant_policy_name` | Grant policy name; null means `<display_name>-key-grants`.     | `string`      | `null`      |    no    |
| `freeform_tags`  | Free-form tags applied to the vault, keys and grant policy.       | `map(string)` | `{}`        |    no    |
| `defined_tags`   | Defined tags applied to the vault, keys and grant policy, keyed `namespace.key`. | `map(string)` | `{}` | no |

### `keys` entries and the `key` object

Both take the same attributes.

| Attribute                   | Type     | Default          | Description                                                       |
|-----------------------------|----------|------------------|-------------------------------------------------------------------|
| `display_name`              | `string` | n/a (required)   | Name of the key.                                                  |
| `algorithm`                 | `string` | `"AES"`          | `AES`, `RSA` or `ECDSA`.                                          |
| `length`                    | `number` | per algorithm    | Key length in bytes. See the table above.                         |
| `curve_id`                  | `string` | `null`           | `NIST_P256`, `NIST_P384` or `NIST_P521`. ECDSA only.              |
| `protection_mode`           | `string` | `"HSM"`          | `HSM` or `SOFTWARE`.                                              |
| `rotation_interval_in_days` | `number` | `null`           | 60-365 to enable automatic rotation; `null` keeps rotation manual. |
| `grant_services`            | `list(string)` | `[]`       | Services allowed to `use keys` on this key, e.g. `blockstorage`, `objectstorage-<region>`. |
| `grant_groups`              | `list(string)` | `[]`       | Groups allowed to `use key-delegate` on this key; `'Domain'/'Group'` outside the Default domain. |

## Outputs

| Name                  | Description                                       |
|-----------------------|---------------------------------------------------|
| `vault_id`            | OCID of the vault.                                |
| `management_endpoint` | Management endpoint of the vault.                 |
| `crypto_endpoint`     | Cryptographic endpoint of the vault.              |
| `key_id`              | OCID of the key from the single `key` input, if requested. |
| `key_ids`             | OCIDs of all keys, keyed by `keys` map key (`key` appears as `default`). |
| `grant_statements`    | Key grant policy statements, also when the module does not attach them. |
| `grant_policy_id`     | OCID of the key grant policy, or null.            |
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
