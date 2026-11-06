variable "compartment_id" {
  description = "OCID of the compartment in which to create the vault and its keys."
  type        = string
}

variable "display_name" {
  description = "Human-readable name for the vault."
  type        = string
}

variable "vault_type" {
  description = "Type of the vault."
  type        = string
  default     = "DEFAULT"

  validation {
    condition     = contains(["DEFAULT", "VIRTUAL_PRIVATE"], var.vault_type)
    error_message = "vault_type must be DEFAULT or VIRTUAL_PRIVATE."
  }
}

variable "key" {
  description = <<-EOT
    Optional single master encryption key to create in the vault. Kept for backwards
    compatibility; new configurations should use `keys`. When set, this key is managed as
    the `default` entry of `keys` (output `key_ids["default"]`, and also `key_id`), so
    `keys` must not contain a `default` entry at the same time.

      * `display_name`              - Name of the key.
      * `algorithm`                 - AES, RSA or ECDSA. Defaults to AES.
      * `length`                    - Key length in *bytes*, not bits. AES accepts 16/24/32
                                      (AES-128/192/256), RSA accepts 256/384/512 (2048/3072/4096-bit),
                                      ECDSA accepts 32/48/66 (NIST_P256/P384/P521). Leave null to get
                                      the module default for the chosen algorithm: AES-256, RSA-4096,
                                      or the length matching `curve_id` for ECDSA.
      * `curve_id`                  - ECDSA curve: NIST_P256, NIST_P384 or NIST_P521. Only valid when
                                      `algorithm` is ECDSA, where it defaults to NIST_P521.
      * `protection_mode`           - HSM (default) keeps key material inside a FIPS 140-2 Level 3 HSM
                                      and never lets it out. SOFTWARE keys are stored and used in
                                      software and can be exported.
      * `rotation_interval_in_days` - Enables automatic key rotation at this interval, 60-365 days.
                                      Null (the default) leaves rotation manual.
      * `grant_services`            - OCI service principals allowed to use this key, for example
                                      `blockstorage`, `objectstorage-eu-frankfurt-1`, `oke`, `streaming`.
                                      See `grant_policy_compartment_id` and the README.
      * `grant_groups`              - IAM groups allowed to associate this key with resources
                                      (`use key-delegate`). Use `'Domain'/'Group'` for groups outside
                                      the Default identity domain.

    Changing `algorithm`, `length`, `curve_id` or `protection_mode` on an existing key replaces it:
    Terraform schedules the old key for deletion and creates a new one. Anything still encrypted
    under the old key must be re-wrapped before the deletion window expires. See the README.
  EOT

  type = object({
    display_name              = string
    algorithm                 = optional(string, "AES")
    length                    = optional(number)
    curve_id                  = optional(string)
    protection_mode           = optional(string, "HSM")
    rotation_interval_in_days = optional(number)
    grant_services            = optional(list(string), [])
    grant_groups              = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.key == null ? true : contains(["AES", "RSA", "ECDSA"], var.key.algorithm)
    error_message = "key.algorithm must be AES, RSA, or ECDSA."
  }

  validation {
    condition     = var.key == null ? true : contains(["HSM", "SOFTWARE"], var.key.protection_mode)
    error_message = "key.protection_mode must be HSM or SOFTWARE. EXTERNAL keys are not supported by this module because they require an external key manager reference."
  }

  validation {
    condition = alltrue([
      for k in(var.key == null ? [] : [var.key]) :
      k.curve_id == null || (k.algorithm == "ECDSA" && contains(["NIST_P256", "NIST_P384", "NIST_P521"], coalesce(k.curve_id, "")))
    ])
    error_message = "key.curve_id may only be set when key.algorithm is ECDSA, and must be NIST_P256, NIST_P384, or NIST_P521."
  }

  validation {
    condition = alltrue([
      for k in(var.key == null ? [] : [var.key]) :
      k.length == null || contains(
        lookup({ AES = [16, 24, 32], RSA = [256, 384, 512], ECDSA = [32, 48, 66] }, k.algorithm, []),
        coalesce(k.length, 0)
      )
    ])
    error_message = "key.length is expressed in BYTES, not bits: AES accepts 16/24/32, RSA accepts 256/384/512, ECDSA accepts 32/48/66. Leave it null to use the module default for the algorithm."
  }

  validation {
    condition = alltrue([
      for k in(var.key == null ? [] : [var.key]) :
      k.algorithm != "ECDSA" || k.length == null || k.curve_id == null ||
      coalesce(k.length, 0) == lookup({ NIST_P256 = 32, NIST_P384 = 48, NIST_P521 = 66 }, coalesce(k.curve_id, ""), 0)
    ])
    error_message = "For ECDSA, key.length must match key.curve_id: NIST_P256 is 32, NIST_P384 is 48, NIST_P521 is 66. Leave key.length null to have it derived from the curve."
  }

  validation {
    condition = alltrue([
      for k in(var.key == null ? [] : [var.key]) :
      k.rotation_interval_in_days == null || (coalesce(k.rotation_interval_in_days, 0) >= 60 && coalesce(k.rotation_interval_in_days, 0) <= 365)
    ])
    error_message = "key.rotation_interval_in_days must be between 60 and 365 days, or null to leave automatic rotation disabled."
  }

  validation {
    condition = alltrue([
      for s in(var.key == null ? [] : var.key.grant_services) :
      can(regex("^[A-Za-z][A-Za-z0-9-]*$", s))
    ])
    error_message = "key.grant_services entries must be bare OCI service names such as blockstorage, objectstorage-eu-frankfurt-1, oke or streaming."
  }

  validation {
    condition = alltrue([
      for g in(var.key == null ? [] : var.key.grant_groups) :
      can(regex("^([A-Za-z0-9._-]+|'[^'\\n]+'(/'[^'\\n]+')?)$", g))
    ])
    error_message = "key.grant_groups entries must be a group name (letters, digits, '.', '_', '-'), a quoted 'Group', or 'Domain'/'Group'."
  }
}

variable "keys" {
  description = <<-EOT
    Master encryption keys to create in the vault, keyed by a stable name that becomes the
    resource key and the key of the `key_ids` output. Each entry takes the same attributes as
    `key` (see its description and the README), with the same defaults: AES-256, HSM, manual
    rotation and no grants. Renaming a map key replaces that key.
  EOT

  type = map(object({
    display_name              = string
    algorithm                 = optional(string, "AES")
    length                    = optional(number)
    curve_id                  = optional(string)
    protection_mode           = optional(string, "HSM")
    rotation_interval_in_days = optional(number)
    grant_services            = optional(list(string), [])
    grant_groups              = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for name in keys(var.keys) : can(regex("^[A-Za-z0-9_-]+$", name))])
    error_message = "keys map keys may contain only letters, digits, underscores and hyphens."
  }

  validation {
    condition     = alltrue([for k in values(var.keys) : contains(["AES", "RSA", "ECDSA"], k.algorithm)])
    error_message = "keys[*].algorithm must be AES, RSA, or ECDSA."
  }

  validation {
    condition     = alltrue([for k in values(var.keys) : contains(["HSM", "SOFTWARE"], k.protection_mode)])
    error_message = "keys[*].protection_mode must be HSM or SOFTWARE. EXTERNAL keys are not supported by this module because they require an external key manager reference."
  }

  validation {
    condition = alltrue([
      for k in values(var.keys) :
      k.curve_id == null || (k.algorithm == "ECDSA" && contains(["NIST_P256", "NIST_P384", "NIST_P521"], coalesce(k.curve_id, "")))
    ])
    error_message = "keys[*].curve_id may only be set when algorithm is ECDSA, and must be NIST_P256, NIST_P384, or NIST_P521."
  }

  validation {
    condition = alltrue([
      for k in values(var.keys) :
      k.length == null || contains(
        lookup({ AES = [16, 24, 32], RSA = [256, 384, 512], ECDSA = [32, 48, 66] }, k.algorithm, []),
        coalesce(k.length, 0)
      )
    ])
    error_message = "keys[*].length is expressed in BYTES, not bits: AES accepts 16/24/32, RSA accepts 256/384/512, ECDSA accepts 32/48/66. Leave it null to use the module default for the algorithm."
  }

  validation {
    condition = alltrue([
      for k in values(var.keys) :
      k.algorithm != "ECDSA" || k.length == null || k.curve_id == null ||
      coalesce(k.length, 0) == lookup({ NIST_P256 = 32, NIST_P384 = 48, NIST_P521 = 66 }, coalesce(k.curve_id, ""), 0)
    ])
    error_message = "For ECDSA, keys[*].length must match curve_id: NIST_P256 is 32, NIST_P384 is 48, NIST_P521 is 66. Leave length null to have it derived from the curve."
  }

  validation {
    condition = alltrue([
      for k in values(var.keys) :
      k.rotation_interval_in_days == null || (coalesce(k.rotation_interval_in_days, 0) >= 60 && coalesce(k.rotation_interval_in_days, 0) <= 365)
    ])
    error_message = "keys[*].rotation_interval_in_days must be between 60 and 365 days, or null to leave automatic rotation disabled."
  }

  validation {
    condition = alltrue(flatten([
      for k in values(var.keys) : [for s in k.grant_services : can(regex("^[A-Za-z][A-Za-z0-9-]*$", s))]
    ]))
    error_message = "keys[*].grant_services entries must be bare OCI service names such as blockstorage, objectstorage-eu-frankfurt-1, oke or streaming."
  }

  validation {
    condition = alltrue(flatten([
      for k in values(var.keys) : [for g in k.grant_groups : can(regex("^([A-Za-z0-9._-]+|'[^'\\n]+'(/'[^'\\n]+')?)$", g))]
    ]))
    error_message = "keys[*].grant_groups entries must be a group name (letters, digits, '.', '_', '-'), a quoted 'Group', or 'Domain'/'Group'."
  }
}

variable "create_grant_policy" {
  description = "Create the IAM policy for `grant_services` and `grant_groups`. Set to false when the provider is not in the tenancy's home region (OCI accepts IAM writes only there) and attach the `grant_statements` output yourself."
  type        = bool
  default     = true
}

variable "grant_policy_compartment_id" {
  description = "OCID of the compartment (or the tenancy) to attach the key grant policy to. Null attaches it to `compartment_id`. The policy is created only when some key has `grant_services` or `grant_groups`."
  type        = string
  default     = null
}

variable "grant_policy_name" {
  description = "Name of the key grant policy. Null derives `<display_name>-key-grants`, with characters other than letters, digits, `.`, `_` and `-` replaced by `-`. Policy names are unique per tenancy."
  type        = string
  default     = null

  validation {
    condition     = var.grant_policy_name == null || can(regex("^[A-Za-z0-9._-]+$", coalesce(var.grant_policy_name, "-")))
    error_message = "grant_policy_name may contain only letters, digits, '.', '_' and '-'."
  }
}

variable "freeform_tags" {
  description = "Free-form tags applied to the vault, keys and grant policy."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags applied to the vault, keys and grant policy, keyed as \"namespace.key\"."
  type        = map(string)
  default     = {}
}
