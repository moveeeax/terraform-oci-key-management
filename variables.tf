variable "compartment_id" {
  description = "OCID of the compartment in which to create the vault."
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
  description = "Optional master encryption key to create in the vault. Null creates only the vault."
  type = object({
    display_name    = string
    algorithm       = optional(string, "AES")
    length          = optional(number, 32)
    protection_mode = optional(string, "HSM")
  })
  default = null

  validation {
    condition     = var.key == null ? true : contains(["AES", "RSA", "ECDSA"], var.key.algorithm)
    error_message = "key.algorithm must be AES, RSA, or ECDSA."
  }
}

variable "freeform_tags" {
  description = "Free-form tags applied to the vault and key."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags applied to the vault and key, keyed as \"namespace.key\"."
  type        = map(string)
  default     = {}
}
