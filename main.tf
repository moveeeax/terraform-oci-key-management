locals {
  # oci_kms_key.key_shape.length is expressed in BYTES, not bits.
  ecdsa_curve_length = {
    NIST_P256 = 32
    NIST_P384 = 48
    NIST_P521 = 66
  }

  # Defaults chosen for strength rather than speed: AES-256 and RSA-4096.
  default_key_length = {
    AES = 32
    RSA = 512
  }

  # The provider lets OCI default an unset curve_id to NIST_P256, which would not match
  # the length derived below, so pin it explicitly for ECDSA and leave it null otherwise.
  key_curve_id = try(var.key.algorithm, null) == "ECDSA" ? coalesce(try(var.key.curve_id, null), "NIST_P521") : null

  # Each candidate is wrapped so that an inapplicable one yields null instead of an
  # error; the outer try covers var.key being null altogether.
  key_length = try(coalesce(
    var.key.length,
    try(local.ecdsa_curve_length[local.key_curve_id], null),
    try(local.default_key_length[var.key.algorithm], null),
  ), null)
}

resource "oci_kms_vault" "this" {
  compartment_id = var.compartment_id
  display_name   = var.display_name
  vault_type     = var.vault_type

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  # time_of_deletion is deliberately left unset. Destroying the vault calls
  # ScheduleVaultDeletion, and an unset deletion time makes OCI apply its maximum
  # 30-day recovery window (the API accepts 7-30 days). Until that window expires the
  # vault and every key in it can be restored with
  # `oci kms management vault cancel-deletion`.
}

resource "oci_kms_key" "this" {
  count = var.key != null ? 1 : 0

  compartment_id      = var.compartment_id
  display_name        = var.key.display_name
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = var.key.protection_mode

  key_shape {
    algorithm = var.key.algorithm
    length    = local.key_length
    curve_id  = local.key_curve_id
  }

  # Automatic rotation issues a new key version on a schedule. Earlier versions stay
  # usable for decryption, so enabling it is additive and destroys no key material.
  is_auto_rotation_enabled = var.key.rotation_interval_in_days != null

  dynamic "auto_key_rotation_details" {
    for_each = var.key.rotation_interval_in_days != null ? [var.key.rotation_interval_in_days] : []

    content {
      rotation_interval_in_days = auto_key_rotation_details.value
    }
  }

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  # As with the vault, time_of_deletion is left unset so that a destroy schedules the
  # key for deletion 30 days out rather than at the earliest permitted time.
}
