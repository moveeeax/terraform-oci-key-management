resource "oci_kms_vault" "this" {
  compartment_id = var.compartment_id
  display_name   = var.display_name
  vault_type     = var.vault_type

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_kms_key" "this" {
  count = var.key != null ? 1 : 0

  compartment_id      = var.compartment_id
  display_name        = var.key.display_name
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = var.key.protection_mode

  key_shape {
    algorithm = var.key.algorithm
    length    = var.key.length
  }

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}
