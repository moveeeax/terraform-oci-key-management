# terraform-oci-key-management

Terraform module that manages an [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/)
Key Management (KMS) vault and, optionally, a master encryption key inside it. Vaults hold
keys and secrets and expose the management and crypto endpoints used by other services.

## Usage

```hcl
module "key_management" {
  source = "github.com/cybercapybara/terraform-oci-key-management"

  compartment_id = var.compartment_id
  display_name   = "prod-vault"
  vault_type     = "DEFAULT"

  key = {
    display_name = "prod-data-key"
    algorithm    = "AES"
    length       = 32
  }

  freeform_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| oci       | >= 5.0   |

## Inputs

| Name             | Description                                                       | Type          | Default     | Required |
|------------------|-------------------------------------------------------------------|---------------|-------------|:--------:|
| `compartment_id` | OCID of the compartment in which to create the vault.             | `string`      | n/a         |   yes    |
| `display_name`   | Human-readable name for the vault.                                | `string`      | n/a         |   yes    |
| `vault_type`     | Vault type (`DEFAULT` or `VIRTUAL_PRIVATE`).                      | `string`      | `"DEFAULT"` |    no    |
| `key`            | Optional master encryption key to create in the vault.            | `object(...)` | `null`      |    no    |
| `freeform_tags`  | Free-form tags applied to the vault and key.                      | `map(string)` | `{}`        |    no    |
| `defined_tags`   | Defined tags applied to the vault and key, keyed `namespace.key`. | `map(string)` | `{}`        |    no    |

## Outputs

| Name                  | Description                                       |
|-----------------------|---------------------------------------------------|
| `vault_id`            | OCID of the vault.                                |
| `management_endpoint` | Management endpoint of the vault.                 |
| `crypto_endpoint`     | Cryptographic endpoint of the vault.              |
| `key_id`              | OCID of the created key, if requested.            |
| `state`               | Lifecycle state of the vault.                     |

## License

[MIT](LICENSE)
