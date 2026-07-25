provider "oci" {}

module "key_management" {
  source = "../.."

  compartment_id = var.compartment_id
  display_name   = "example-vault"
  vault_type     = "DEFAULT"

  key = {
    display_name = "example-key"

    # AES-256 in the HSM is what you get without these lines; they are spelled out to
    # show that length is in bytes rather than bits.
    algorithm       = "AES"
    length          = 32
    protection_mode = "HSM"

    rotation_interval_in_days = 90
  }

  freeform_tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

variable "compartment_id" {
  description = "Compartment OCID to deploy the example vault into."
  type        = string
}

output "vault_id" {
  value = module.key_management.vault_id
}
