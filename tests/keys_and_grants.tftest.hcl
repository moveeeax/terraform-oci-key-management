# Requires Terraform >= 1.7 for mock_provider. See tests/key_shape.tftest.hcl.

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaaexamplecompartment"
  display_name   = "test vault"
}

run "several_keys_share_one_vault" {
  variables {
    keys = {
      volumes = {
        display_name = "volumes-key"
      }
      signing = {
        display_name = "signing-key"
        algorithm    = "RSA"
      }
      tokens = {
        display_name = "tokens-key"
        algorithm    = "ECDSA"
        curve_id     = "NIST_P384"
      }
    }
  }

  assert {
    condition     = length(oci_kms_key.this) == 3
    error_message = "Every entry of keys should create one key."
  }

  assert {
    condition     = alltrue([for k in values(oci_kms_key.this) : k.management_endpoint == oci_kms_vault.this.management_endpoint])
    error_message = "All keys should be created in the module's single vault."
  }

  assert {
    condition     = oci_kms_key.this["volumes"].key_shape[0].length == 32 && oci_kms_key.this["signing"].key_shape[0].length == 512 && oci_kms_key.this["tokens"].key_shape[0].length == 48
    error_message = "Each key should get the length defaults of its own algorithm and curve."
  }

  assert {
    condition     = local.key_curve_ids["volumes"] == null && local.key_curve_ids["tokens"] == "NIST_P384"
    error_message = "curve_id should be pinned only for ECDSA keys."
  }

  assert {
    condition     = keys(output.key_ids) == ["signing", "tokens", "volumes"] && output.key_ids["volumes"] == oci_kms_key.this["volumes"].id
    error_message = "key_ids should map every keys entry to its OCID."
  }

  assert {
    condition     = output.key_id == null
    error_message = "key_id belongs to the single key input and should stay null when only keys is used."
  }

  assert {
    condition     = length(oci_identity_policy.key_grants) == 0 && length(output.grant_statements) == 0
    error_message = "No grant policy should be created when no key lists grants."
  }
}

# The single key input keeps working and lives at the "default" address, which the moved
# block maps from the pre-keys oci_kms_key.this[0].
run "single_key_input_is_the_default_entry" {
  variables {
    key = {
      display_name = "legacy-key"
    }
    keys = {
      extra = {
        display_name = "extra-key"
      }
    }
  }

  assert {
    condition     = length(oci_kms_key.this) == 2 && oci_kms_key.this["default"].display_name == "legacy-key"
    error_message = "key should be created as keys[\"default\"] alongside the keys entries."
  }

  assert {
    condition     = output.key_id == oci_kms_key.this["default"].id && output.key_ids["default"] == output.key_id
    error_message = "key_id should keep returning the single key's OCID."
  }
}

run "grants_are_scoped_to_each_key_and_compartment" {
  variables {
    keys = {
      volumes = {
        display_name   = "volumes-key"
        grant_services = ["blockstorage", "oke"]
        grant_groups   = ["VolumeWriters", "'Ops'/'ClusterAdmins'"]
      }
      buckets = {
        display_name   = "buckets-key"
        grant_services = ["objectstorage-eu-frankfurt-1"]
      }
      unused = {
        display_name = "unused-key"
      }
    }
  }

  assert {
    condition     = length(oci_identity_policy.key_grants) == 1
    error_message = "One grant policy should be created when any key lists grants."
  }

  assert {
    condition     = oci_identity_policy.key_grants[0].compartment_id == var.compartment_id
    error_message = "The grant policy should default to the vault's compartment."
  }

  assert {
    condition     = oci_identity_policy.key_grants[0].name == "test-vault-key-grants"
    error_message = "The derived policy name should replace characters OCI rejects."
  }

  assert {
    condition = toset(oci_identity_policy.key_grants[0].statements) == toset([
      "Allow service blockstorage, oke to use keys in compartment id ${var.compartment_id} where target.key.id = '${oci_kms_key.this["volumes"].id}'",
      "Allow service objectstorage-eu-frankfurt-1 to use keys in compartment id ${var.compartment_id} where target.key.id = '${oci_kms_key.this["buckets"].id}'",
      "Allow group VolumeWriters, 'Ops'/'ClusterAdmins' to use key-delegate in compartment id ${var.compartment_id} where target.key.id = '${oci_kms_key.this["volumes"].id}'",
    ])
    error_message = "Statements should name only the listed services and groups, the keys' compartment and the one key each grant is for."
  }

  assert {
    condition     = output.grant_policy_id == oci_identity_policy.key_grants[0].id
    error_message = "grant_policy_id should expose the policy OCID."
  }
}

run "single_key_input_accepts_grants" {
  variables {
    key = {
      display_name   = "legacy-key"
      grant_services = ["blockstorage"]
    }
    grant_policy_compartment_id = "ocid1.tenancy.oc1..aaaaaaaaexampletenancy"
    grant_policy_name           = "custom-grants"
  }

  assert {
    condition     = oci_identity_policy.key_grants[0].compartment_id == "ocid1.tenancy.oc1..aaaaaaaaexampletenancy" && oci_identity_policy.key_grants[0].name == "custom-grants"
    error_message = "grant_policy_compartment_id and grant_policy_name should override the defaults."
  }

  assert {
    condition     = length(oci_identity_policy.key_grants[0].statements) == 1
    error_message = "One service statement is expected for the single key."
  }
}

run "statements_without_policy_when_disabled" {
  variables {
    keys = {
      volumes = {
        display_name   = "volumes-key"
        grant_services = ["blockstorage"]
      }
    }
    create_grant_policy = false
  }

  assert {
    condition     = length(oci_identity_policy.key_grants) == 0 && output.grant_policy_id == null
    error_message = "create_grant_policy = false should skip the policy."
  }

  assert {
    condition     = length(output.grant_statements) == 1
    error_message = "grant_statements should still be exposed so the caller can attach them."
  }
}

run "rejects_default_entry_next_to_key" {
  variables {
    key = {
      display_name = "legacy-key"
    }
    keys = {
      default = {
        display_name = "clash"
      }
    }
  }

  command         = plan
  expect_failures = [oci_kms_vault.this]
}
