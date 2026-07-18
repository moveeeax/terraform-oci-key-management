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
  description = "OCID of the created master encryption key, if one was requested."
  value       = try(oci_kms_key.this[0].id, null)
}

output "state" {
  description = "Lifecycle state of the vault."
  value       = oci_kms_vault.this.state
}
