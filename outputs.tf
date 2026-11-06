output "vault_id" {
  description = "OCID of the vault."
  value       = oci_kms_vault.this.id
}

output "management_endpoint" {
  description = "Management endpoint of the vault, used for key operations."
  value       = oci_kms_vault.this.management_endpoint
}

output "crypto_endpoint" {
  description = "Cryptographic endpoint of the vault, used for encrypt/decrypt operations."
  value       = oci_kms_vault.this.crypto_endpoint
}

output "key_id" {
  description = "OCID of the key created from the single `key` input, if one was requested. Keys from `keys` are in `key_ids`."
  value       = try(oci_kms_key.this["default"].id, null)
}

output "key_ids" {
  description = "OCIDs of all keys in the vault, keyed by their `keys` map key. The single `key` input appears as \"default\"."
  value       = { for name, k in oci_kms_key.this : name => k.id }
}

output "grant_statements" {
  description = "IAM policy statements that let the configured services and groups use the keys. Attached by the module unless create_grant_policy is false."
  value       = local.grant_statements
}

output "grant_policy_id" {
  description = "OCID of the key grant policy, or null when no grant policy was created."
  value       = try(oci_identity_policy.key_grants[0].id, null)
}

output "state" {
  description = "Lifecycle state of the vault."
  value       = oci_kms_vault.this.state
}
