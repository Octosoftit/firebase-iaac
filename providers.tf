terraform {
  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "4.11.0"
    }
    null = {
      version = "~> 3.1.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.7.2"
    }
  }
}
