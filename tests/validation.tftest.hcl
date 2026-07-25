# Requires Terraform >= 1.7 for mock_provider. See tests/key_shape.tftest.hcl.

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaaexamplecompartment"
  display_name   = "test-vault"
}

run "rejects_invalid_vault_type" {
  variables {
    vault_type = "PUBLIC"
  }

  command         = plan
  expect_failures = [var.vault_type]
}

run "rejects_invalid_algorithm" {
  variables {
    key = {
      display_name = "bad-key"
      algorithm    = "Blowfish"
    }
  }

  command         = plan
  expect_failures = [var.key]
}

# EXTERNAL protection mode needs an external key manager reference this module does not
# model, so it must be rejected at plan time rather than at apply time.
run "rejects_unsupported_protection_mode" {
  variables {
    key = {
      display_name    = "bad-key"
      protection_mode = "EXTERNAL"
    }
  }

  command         = plan
  expect_failures = [var.key]
}

# 32 is a valid AES length but not a valid RSA one; without this check the mistake only
# surfaces at apply, after the vault has already been created.
run "rejects_length_that_does_not_match_algorithm" {
  variables {
    key = {
      display_name = "bad-key"
      algorithm    = "RSA"
      length       = 32
    }
  }

  command         = plan
  expect_failures = [var.key]
}

run "rejects_aes_128_style_typo_in_bits" {
  variables {
    key = {
      display_name = "bad-key"
      algorithm    = "AES"
      length       = 256
    }
  }

  command         = plan
  expect_failures = [var.key]
}

run "rejects_curve_id_on_non_ecdsa_key" {
  variables {
    key = {
      display_name = "bad-key"
      algorithm    = "AES"
      curve_id     = "NIST_P256"
    }
  }

  command         = plan
  expect_failures = [var.key]
}

run "rejects_unknown_curve" {
  variables {
    key = {
      display_name = "bad-key"
      algorithm    = "ECDSA"
      curve_id     = "secp256k1"
    }
  }

  command         = plan
  expect_failures = [var.key]
}

run "rejects_curve_and_length_mismatch" {
  variables {
    key = {
      display_name = "bad-key"
      algorithm    = "ECDSA"
      curve_id     = "NIST_P384"
      length       = 32
    }
  }

  command         = plan
  expect_failures = [var.key]
}

run "rejects_rotation_interval_below_minimum" {
  variables {
    key = {
      display_name              = "bad-key"
      rotation_interval_in_days = 30
    }
  }

  command         = plan
  expect_failures = [var.key]
}

run "rejects_rotation_interval_above_maximum" {
  variables {
    key = {
      display_name              = "bad-key"
      rotation_interval_in_days = 400
    }
  }

  command         = plan
  expect_failures = [var.key]
}
