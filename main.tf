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

  # The single `key` input is managed as this entry of the keys map, so that both inputs
  # share one resource. The moved block below carries keys created before `keys` existed.
  legacy_key_name = "default"

  requested_keys = merge(
    var.keys,
    var.key == null ? {} : { (local.legacy_key_name) = var.key },
  )

  # The provider lets OCI default an unset curve_id to NIST_P256, which would not match
  # the length derived below, so pin it explicitly for ECDSA and leave it null otherwise.
  key_curve_ids = {
    for name, k in local.requested_keys :
    name => k.algorithm == "ECDSA" ? coalesce(k.curve_id, "NIST_P521") : null
  }

  # Each candidate is wrapped so that an inapplicable one yields null instead of an error.
  key_lengths = {
    for name, k in local.requested_keys :
    name => coalesce(
      k.length,
      try(local.ecdsa_curve_length[local.key_curve_ids[name]], null),
      try(local.default_key_length[k.algorithm], null),
    )
  }

  # One statement per grant kind per key, each limited to that key's OCID and to the
  # compartment that holds the keys.
  service_grant_statements = [
    for name, k in local.requested_keys :
    format(
      "Allow service %s to use keys in compartment id %s where target.key.id = '%s'",
      join(", ", k.grant_services), var.compartment_id, oci_kms_key.this[name].id,
    )
    if length(k.grant_services) > 0
  ]

  group_grant_statements = [
    for name, k in local.requested_keys :
    format(
      "Allow group %s to use key-delegate in compartment id %s where target.key.id = '%s'",
      join(", ", k.grant_groups), var.compartment_id, oci_kms_key.this[name].id,
    )
    if length(k.grant_groups) > 0
  ]

  grant_statements = concat(local.service_grant_statements, local.group_grant_statements)

  # Decided from inputs only, so the policy's count is known at plan time even though the
  # statements wait for the key OCIDs.
  create_grant_policy = var.create_grant_policy && anytrue([
    for k in values(local.requested_keys) : length(k.grant_services) + length(k.grant_groups) > 0
  ])

  grant_policy_name = coalesce(
    var.grant_policy_name,
    "${replace(var.display_name, "/[^A-Za-z0-9._-]/", "-")}-key-grants",
  )
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

  lifecycle {
    precondition {
      condition     = var.key == null || !contains(keys(var.keys), local.legacy_key_name)
      error_message = "keys must not contain a \"default\" entry while key is set: key is managed as keys[\"default\"]. Move key into keys and drop key instead."
    }
  }
}

# Before `keys` existed the single key was oci_kms_key.this[0]. It is now the "default"
# entry, and this block moves it in state instead of replacing it.
moved {
  from = oci_kms_key.this[0]
  to   = oci_kms_key.this["default"]
}

resource "oci_kms_key" "this" {
  for_each = local.requested_keys

  compartment_id      = var.compartment_id
  display_name        = each.value.display_name
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = each.value.protection_mode

  key_shape {
    algorithm = each.value.algorithm
    length    = local.key_lengths[each.key]
    curve_id  = local.key_curve_ids[each.key]
  }

  # Automatic rotation issues a new key version on a schedule. Earlier versions stay
  # usable for decryption, so enabling it is additive and destroys no key material.
  is_auto_rotation_enabled = each.value.rotation_interval_in_days != null

  dynamic "auto_key_rotation_details" {
    for_each = each.value.rotation_interval_in_days != null ? [each.value.rotation_interval_in_days] : []

    content {
      rotation_interval_in_days = auto_key_rotation_details.value
    }
  }

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  # As with the vault, time_of_deletion is left unset so that a destroy schedules the
  # key for deletion 30 days out rather than at the earliest permitted time.
}

# Lets the named services use, and the named groups delegate, exactly the keys they are
# listed on. OCI rejects CMEK on volumes, buckets and clusters until such a policy exists.
# OCI accepts IAM writes only in the tenancy's home region. Callers whose provider points
# elsewhere set create_grant_policy = false and attach the grant_statements output from a
# home-region provider themselves.
resource "oci_identity_policy" "key_grants" {
  count = local.create_grant_policy ? 1 : 0

  compartment_id = coalesce(var.grant_policy_compartment_id, var.compartment_id)
  name           = local.grant_policy_name
  description    = "Grants use of the keys in vault ${var.display_name} to the services and groups listed on each key."
  statements     = local.grant_statements

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}
