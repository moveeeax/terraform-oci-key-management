provider "oci" {}

module "key_management" {
  source = "../.."

  compartment_id = var.compartment_id
  display_name   = "example-vault"
  vault_type     = "DEFAULT"

  # Several keys share the vault; vaults are billed per vault, keys are not.
  keys = {
    volumes = {
      display_name = "example-volumes-key"

      # AES-256 in the HSM is what you get without these lines; they are spelled out to
      # show that length is in bytes rather than bits.
      algorithm       = "AES"
      length          = 32
      protection_mode = "HSM"

      rotation_interval_in_days = 90

      # Block Volume and OKE may use this key; the group may attach it to volumes.
      grant_services = ["blockstorage", "oke"]
      grant_groups   = ["VolumeAdmins"]
    }

    buckets = {
      display_name   = "example-buckets-key"
      grant_services = ["objectstorage-${var.region}"]
    }
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

variable "region" {
  description = "Region identifier used in the Object Storage service name, for example eu-frankfurt-1. The provider must point at the tenancy's home region for the grant policy to be created."
  type        = string
}

output "vault_id" {
  value = module.key_management.vault_id
}

output "key_ids" {
  value = module.key_management.key_ids
}
