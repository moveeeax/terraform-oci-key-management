provider "oci" {}

module "key_management" {
  source = "../.."

  compartment_id = var.compartment_id
  display_name   = "example-vault"
  vault_type     = "DEFAULT"

  key = {
    display_name = "example-key"
    algorithm    = "AES"
    length       = 32
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
