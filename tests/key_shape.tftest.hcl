# Requires Terraform >= 1.7 for mock_provider. The module itself still targets >= 1.5;
# do not bump required_version in versions.tf on account of this file.
#
# These run against a mocked OCI provider, so no credentials and no network are needed:
#   terraform init -backend=false && terraform test

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaaexamplecompartment"
  display_name   = "test-vault"
}

run "vault_only_when_key_is_null" {
  assert {
    condition     = length(oci_kms_key.this) == 0
    error_message = "No key should be created when var.key is null."
  }

  assert {
    condition     = oci_kms_vault.this.vault_type == "DEFAULT"
    error_message = "vault_type should default to DEFAULT."
  }
}

run "aes_defaults_to_hsm_protected_aes_256" {
  variables {
    key = {
      display_name = "test-key"
    }
  }

  assert {
    condition     = oci_kms_key.this[0].protection_mode == "HSM"
    error_message = "protection_mode should default to HSM so key material never leaves the HSM."
  }

  assert {
    condition     = oci_kms_key.this[0].key_shape[0].algorithm == "AES"
    error_message = "algorithm should default to AES."
  }

  # 32 bytes = AES-256. Anything less would silently be AES-128/192.
  assert {
    condition     = oci_kms_key.this[0].key_shape[0].length == 32
    error_message = "AES keys should default to 32 bytes (AES-256)."
  }

  # curve_id is optional+computed on the resource, so assert on what the module sends
  # rather than on what the provider echoes back.
  assert {
    condition     = local.key_curve_id == null
    error_message = "curve_id must not be set for non-ECDSA keys."
  }

  assert {
    condition     = oci_kms_key.this[0].is_auto_rotation_enabled == false
    error_message = "Automatic rotation should be opt-in."
  }

  assert {
    condition     = length(oci_kms_key.this[0].auto_key_rotation_details) == 0
    error_message = "No rotation schedule should be emitted when rotation_interval_in_days is null."
  }
}

# Before curve_id support was added, an RSA key inherited the AES default length of 32
# bytes, which OCI rejects. The length must now follow the algorithm.
run "rsa_defaults_to_rsa_4096" {
  variables {
    key = {
      display_name = "test-rsa-key"
      algorithm    = "RSA"
    }
  }

  assert {
    condition     = oci_kms_key.this[0].key_shape[0].length == 512
    error_message = "RSA keys should default to 512 bytes (RSA-4096)."
  }
}

# ECDSA needs curve_id; without it the provider defaults the curve to NIST_P256 while
# the length says otherwise, and the create call fails.
run "ecdsa_pins_curve_and_matching_length" {
  variables {
    key = {
      display_name = "test-ecdsa-key"
      algorithm    = "ECDSA"
    }
  }

  assert {
    condition     = oci_kms_key.this[0].key_shape[0].curve_id == "NIST_P521"
    error_message = "ECDSA keys should pin curve_id explicitly rather than inherit the API default."
  }

  assert {
    condition     = oci_kms_key.this[0].key_shape[0].length == 66
    error_message = "ECDSA key length should be derived from the curve (NIST_P521 = 66 bytes)."
  }
}

run "ecdsa_length_follows_explicit_curve" {
  variables {
    key = {
      display_name = "test-ecdsa-p384"
      algorithm    = "ECDSA"
      curve_id     = "NIST_P384"
    }
  }

  assert {
    condition     = oci_kms_key.this[0].key_shape[0].length == 48
    error_message = "NIST_P384 should derive a 48 byte key length."
  }
}

run "explicit_length_is_respected" {
  variables {
    key = {
      display_name = "test-rsa-3072"
      algorithm    = "RSA"
      length       = 384
    }
  }

  assert {
    condition     = oci_kms_key.this[0].key_shape[0].length == 384
    error_message = "An explicitly supplied length must win over the module default."
  }
}

run "rotation_schedule_is_wired_through" {
  variables {
    key = {
      display_name              = "test-rotating-key"
      rotation_interval_in_days = 90
    }
  }

  assert {
    condition     = oci_kms_key.this[0].is_auto_rotation_enabled == true
    error_message = "Setting rotation_interval_in_days should enable automatic rotation."
  }

  assert {
    condition     = oci_kms_key.this[0].auto_key_rotation_details[0].rotation_interval_in_days == 90
    error_message = "The requested rotation interval should reach the resource."
  }
}

run "software_protection_mode_is_allowed" {
  variables {
    key = {
      display_name    = "test-software-key"
      protection_mode = "SOFTWARE"
    }
  }

  assert {
    condition     = oci_kms_key.this[0].protection_mode == "SOFTWARE"
    error_message = "SOFTWARE should remain a supported, explicit opt-out of HSM protection."
  }
}
