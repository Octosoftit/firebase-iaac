variable "project_id" {
  type        = string
  description = "The id of the created project."
  nullable    = false
}

variable "project_name" {
  type        = string
  description = "The name of the created project"
  nullable    = false
}

variable "location" {
  type        = string
  description = "The location to create the project in"
  default     = "europe-west"
  nullable    = false
}
