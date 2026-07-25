terraform {
  # Kept at 1.5 for consumers. The test suite under tests/ uses mock_provider and so
  # needs 1.7 to run, but nothing in the module itself does.
  required_version = ">= 1.5"

  required_providers {
    oci = {
      source = "oracle/oci"
      # Upper bound so a future major release of the provider cannot silently change
      # this module's behaviour.
      version = ">= 5.0, < 9.0"
    }
  }
}
