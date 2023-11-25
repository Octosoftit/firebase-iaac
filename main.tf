locals {
  bucket_location = "EUROPE-WEST1"
}

# Basic provider - given the variables we need to configure it here
provider "google-beta" {
  alias  = "gcloud-user"
  region = var.region
  zone   = var.zone
}
data "google_billing_account" "account" {
  provider        = google-beta.gcloud-user
  billing_account = var.billing_account_id
}
data "google_client_config" "gcloud-user" {
  provider = google-beta.gcloud-user
}
data "google_client_openid_userinfo" "gcloud-user" {
  provider = google-beta.gcloud-user
}

resource "random_id" "project" {
  byte_length = 4
}


# ====================================================== #
#   Section 1: Project and relative service account
#              for IAM
# ====================================================== #

resource "google_project" "default" {
  provider        = google-beta.gcloud-user
  project_id      = var.randomize_project_id ? "${substr(var.project_id, 0, 21)}-${random_id.project.hex}" : var.project_id
  name            = var.project_name
  billing_account = data.google_billing_account.account.id
  org_id          = var.org_id
}

resource "google_service_account" "service_account" {
  provider     = google-beta.gcloud-user
  project      = google_project.default.project_id
  account_id   = var.project_service_account_id
  display_name = var.project_service_account_name
}

resource "google_service_account_iam_member" "grant-token-iam" {
  provider           = google-beta.gcloud-user
  service_account_id = google_service_account.service_account.id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${data.google_client_openid_userinfo.gcloud-user.email}"
}

# ====================================================== #
#   Section 2: Associate the required IAM roles to the
#              service account
# ====================================================== #

locals {
  iam_roles = {
    "firebase-admin-iam" : "roles/firebase.admin",
    "service-usage-admin-iam" : "roles/serviceusage.serviceUsageAdmin",
    "appengine-admin-iam" : "roles/appengine.appAdmin",
    "appengine-creator-iam" : "roles/appengine.appCreator",
    "editor-iam" : "roles/editor"
  }
}

resource "google_project_iam_member" "service-account-iams" {
  for_each = local.iam_roles
  provider = google-beta.gcloud-user
  project  = google_project.default.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_service_account_key" "mykey" {
  provider           = google-beta.gcloud-user
  service_account_id = google_service_account.service_account.id
  depends_on = [
    google_project_iam_member.service-account-iams
    # google_project_iam_member.firebase-admin-iam,
    # google_project_iam_member.service-usage-admin-iam,
  ]
}

resource "time_sleep" "delay_token_creation" {
  depends_on = [
    google_service_account_iam_member.grant-token-iam,
    google_service_account.service_account,
    google_project_iam_member.service-account-iams
  ]

  create_duration = "60s"
}

data "google_service_account_access_token" "default" {
  provider               = google-beta.gcloud-user
  target_service_account = google_service_account.service_account.email
  scopes                 = ["userinfo-email", "cloud-platform"]
  lifetime               = "300s"
  depends_on = [
    google_service_account_iam_member.grant-token-iam,
    google_service_account.service_account,
    google_project_iam_member.service-account-iams,
    time_sleep.delay_token_creation
  ]
}

provider "google-beta" {
  alias        = "service-account"
  project      = google_project.default.project_id
  region       = var.region
  zone         = var.zone
  access_token = data.google_service_account_access_token.default.access_token
}

# ====================================================== #
#   Section 3: Activate the various API on the project
# ====================================================== #

# Activate all required apis
resource "google_project_service" "serviceusage" {
  provider                   = google-beta.gcloud-user
  project                    = google_project.default.project_id
  service                    = "serviceusage.googleapis.com"
  disable_dependent_services = true
  depends_on                 = []
}

resource "google_project_service" "firebase" {
  provider                   = google-beta.service-account
  project                    = google_project.default.project_id
  service                    = "firebase.googleapis.com"
  disable_dependent_services = true
  depends_on = [
    google_project_service.serviceusage
  ]
}

resource "google_project_service" "firestore" {
  provider = google-beta.service-account
  project  = google_project.default.project_id
  service  = "firestore.googleapis.com"
  depends_on = [
    google_project_service.serviceusage
  ]
}

resource "google_project_service" "firebasestorage" {
  provider = google-beta.service-account
  project  = google_project.default.project_id
  service  = "firebasestorage.googleapis.com"
  depends_on = [
    google_project_service.serviceusage
  ]
}

resource "google_project_service" "cloudresourcemanager" {
  provider = google-beta.service-account
  project  = google_project.default.project_id
  service  = "cloudresourcemanager.googleapis.com"
  depends_on = [
    google_project_service.serviceusage
  ]
}

resource "google_project_service" "identitytoolkit" {
  provider = google-beta.service-account
  project  = google_project.default.project_id
  service  = "identitytoolkit.googleapis.com"
  depends_on = [
    google_project_service.serviceusage
  ]
}

resource "google_project_service" "compute" {
  provider = google-beta.service-account
  project  = google_project.default.project_id
  service  = "compute.googleapis.com"
  depends_on = [
    google_project_service.serviceusage
  ]
}

resource "google_project_service" "container_registry" {
  provider                   = google-beta.service-account
  project                    = google_project.default.project_id
  service                    = "containerregistry.googleapis.com"
  disable_dependent_services = true
  depends_on = [
    google_project_service.serviceusage
  ]
}

resource "google_project_service" "cloud_run" {
  provider = google-beta.service-account
  project  = google_project.default.project_id
  service  = "run.googleapis.com"
  depends_on = [
    google_project_service.serviceusage
  ]
}

resource "google_project_service" "cloud_build" {
  provider = google-beta.service-account
  project  = google_project.default.project_id
  service  = "cloudbuild.googleapis.com"
  depends_on = [
    google_project_service.serviceusage
  ]
}

# ====================================================== #
#   Section 4: Creating the Firebase project
# ====================================================== #
module "firebase" {
  source       = "./modules/firebase"
  project_name = var.project_name
  location     = var.location
  project_id   = google_project.default.project_id
  providers = {
    google-beta.service-account = google-beta.service-account
  }

  depends_on = [
    google_project_iam_member.service-account-iams,
    google_project_service.firebase,
    google_project_service.firestore
  ]
}

# # Create a bucket for backups
# resource "google_storage_bucket" "backup" {
#   provider = google-beta.service-account
#   project  = google_project.default.project_id
#   name     = "${google_project.default.project_id}-backup"
#   location = local.bucket_location
# }

# # Create admin-sdk service account
# resource "google_service_account" "admin_sdk" {
#   provider     = google-beta.gcloud-user
#   project      = google_project.default.project_id
#   account_id   = "firebase-adminsdk-ouwu6"
#   display_name = "firebase-adminsdk"
# }
# resource "google_project_iam_member" "admin-sdk-token-creator" {
#   provider = google-beta.gcloud-user
#   project  = google_project.default.project_id
#   role     = "roles/iam.serviceAccountTokenCreator"
#   member   = "serviceAccount:${google_service_account.admin_sdk.email}"
# }
# resource "google_project_iam_member" "admin-sdk-agent" {
#   provider = google-beta.gcloud-user
#   project  = google_project.default.project_id
#   role     = "roles/firebase.sdkAdminServiceAgent"
#   member   = "serviceAccount:${google_service_account.admin_sdk.email}"
# }
# resource "google_service_account_key" "admin_sdk" {
#   provider           = google-beta.gcloud-user
#   service_account_id = google_service_account.service_account.id
#   # Wait for the account being added to roles
#   depends_on = [
#     google_project_iam_member.admin-sdk-token-creator,
#     google_project_iam_member.admin-sdk-agent,
#   ]
# }

# # Create firebase storage
# resource "null_resource" "activate_storage" {
#   triggers = {
#     bucket = data.google_firebase_web_app_config.app.storage_bucket
#   }
#   provisioner "local-exec" {
#     command     = "curl -X POST -H 'Authorization: Bearer ${nonsensitive(data.google_service_account_access_token.default.access_token)}' -H 'Content-Type: application/json' 'https://firebasestorage.googleapis.com/v1beta/projects/${google_project.default.project_id}/buckets/${data.google_firebase_web_app_config.app.storage_bucket}:addFirebase'"
#     interpreter = ["sh", "-c"]
#   }
#   depends_on = [
#     google_firebase_web_app.app,
#     google_project_service.firebasestorage
#   ]
# }

# # Enable authentication service
# resource "google_identity_platform_config" "identity_platform_config" {
#   provider                   = google-beta.service-account
#   project                    = google_project.default.project_id
#   autodelete_anonymous_users = true
#   depends_on = [
#     google_firebase_web_app.app,
#     google_project_service.identitytoolkit
#   ]
# }
# resource "google_identity_platform_project_default_config" "identity_project_config" {
#   provider = google-beta.service-account
#   project  = google_project.default.project_id

#   sign_in {
#     allow_duplicate_emails = false

#     email {
#       enabled           = true
#       password_required = true
#     }
#   }

#   depends_on = [google_identity_platform_config.identity_platform_config]
# }

# # Write secrets to local file
# resource "local_file" "firebase_config" {
#   content = jsonencode({
#     firebase = {
#       appId             = google_firebase_web_app.app.app_id
#       apiKey            = data.google_firebase_web_app_config.app.api_key
#       authDomain        = data.google_firebase_web_app_config.app.auth_domain
#       databaseURL       = lookup(data.google_firebase_web_app_config.app, "database_url", "")
#       storageBucket     = lookup(data.google_firebase_web_app_config.app, "storage_bucket", "")
#       messagingSenderId = lookup(data.google_firebase_web_app_config.app, "messaging_sender_id", "")
#       measurementId     = lookup(data.google_firebase_web_app_config.app, "measurement_id", "")
#     }
#   })
#   filename = "${path.module}/firebase-config.json"
#   depends_on = [
#     google_firebase_web_app.app
#   ]
# }

# resource "local_file" "secrets_file" {
#   content = jsonencode({
#     private = {
#       serviceAccount = jsondecode(base64decode(google_service_account_key.admin_sdk.private_key))
#       firebase = {
#         backupBucket = google_storage_bucket.backup.name
#       }
#     }
#     public = {
#       firebase = {
#         projectId         = google_project.default.project_id
#         appId             = google_firebase_web_app.app.app_id
#         apiKey            = data.google_firebase_web_app_config.app.api_key
#         authDomain        = data.google_firebase_web_app_config.app.auth_domain
#         databaseURL       = lookup(data.google_firebase_web_app_config.app, "database_url", "")
#         storageBucket     = lookup(data.google_firebase_web_app_config.app, "storage_bucket", "")
#         messagingSenderId = lookup(data.google_firebase_web_app_config.app, "messaging_sender_id", "")
#         measurementId     = lookup(data.google_firebase_web_app_config.app, "measurement_id", "")
#       }
#     }
#   })
#   filename = "${path.module}/secrets.json"
#   depends_on = [
#     google_firebase_web_app.app
#   ]
# }

# resource "local_file" "firebaserc" {
#   content = jsonencode({
#     projects = {
#       development = google_project.default.project_id
#       production  = google_project.default.project_id
#     }
#   })
#   filename = "${path.module}/.firebaserc"
#   depends_on = [
#     google_project.default
#   ]
# }


# resource "local_file" "admin_config" {
#   content  = base64decode(google_service_account_key.mykey.private_key)
#   filename = "${path.module}/admin-config.json"
#   depends_on = [
#     google_service_account_key.mykey,
#     google_firebase_web_app.app
#   ]
# }
