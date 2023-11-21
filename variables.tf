variable "billing_account_id" {
  type        = string
  description = "The id of the associated billing account"
  nullable    = false
}
variable "project_id" {
  type        = string
  description = "The id of the created project"
  nullable    = false
}
variable "project_name" {
  type        = string
  description = "The name of the created project"
  nullable    = false
}
variable "region" {
  type        = string
  description = "The region to create the project in"
  default     = "europe-west1"
  nullable    = false
}
variable "zone" {
  type        = string
  description = "The zone to create the project in"
  default     = "europe-west1-b"
  nullable    = false
}
variable "location" {
  type        = string
  description = "The location to create the project in"
  default     = "europe-west"
  nullable    = false
}

variable "project_service_account_id" {
  type        = string
  description = "The account id of the main service account associated to the project"
  default     = "iaac"
  nullable    = false
}

variable "project_service_account_name" {
  type        = string
  description = "The display name of the main service account associated to the project"
  default     = "Iaac Automation"
  nullable    = false
}
