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

locals {
  enable_authentication_service = var.enable_authentication_service
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

resource "google_service_account_key" "sa_key" {
  provider           = google-beta.gcloud-user
  service_account_id = google_service_account.service_account.id
  depends_on = [
    google_project_iam_member.service-account-iams
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
  source              = "./modules/firebase"
  project_name        = var.project_name
  location            = var.location
  project_id          = google_project.default.project_id
  resource_suffix     = var.randomize_project_id ? random_id.project.hex : ""
  gcp_sa_access_token = data.google_service_account_access_token.default.access_token

  providers = {
    google-beta.service-account = google-beta.service-account
    google-beta.gcloud-user     = google-beta.gcloud-user
  }

  depends_on = [
    google_project_iam_member.service-account-iams,
    google_project_service.firebase,
    google_project_service.firestore,
    google_project_service.firebasestorage,
    google_project_service.identitytoolkit
  ]
}

# ====================================================== #
#   Section 5: Enables the Authentication Service
# ====================================================== #
resource "google_identity_platform_config" "identity_platform_config" {
  count                      = local.enable_authentication_service ? 1 : 0
  project                    = google_project.default.project_id
  autodelete_anonymous_users = true
  sign_in {
    allow_duplicate_emails = false
    email {
      enabled           = true
      password_required = true
    }
  }
  depends_on = [
    module.firebase,
  ]
}

# ====================================================== #
#   Section 6: Outputs secrets to local file for
#              futher integrations
# ====================================================== #
resource "local_file" "firebase_config" {
  content = jsonencode({
    firebase = {
      appId             = module.firebase.app.app_id
      apiKey            = module.firebase.app_config.api_key
      authDomain        = module.firebase.app_config.auth_domain
      databaseURL       = lookup(module.firebase.app_config, "database_url", "")
      storageBucket     = lookup(module.firebase.app_config, "storage_bucket", "")
      messagingSenderId = lookup(module.firebase.app_config, "messaging_sender_id", "")
      measurementId     = lookup(module.firebase.app_config, "measurement_id", "")
    }
  })
  filename = "${path.module}/firebase-config.json"
  depends_on = [
    module.firebase
  ]
}

resource "local_file" "secrets_file" {
  content = jsonencode({
    private = {
      serviceAccount = jsondecode(base64decode(module.firebase.admin_sdk_account_key.private_key))
      firebase = {
        backupBucket = module.firebase.app_backup_bucket.name
      }
    }
    public = {
      firebase = {
        projectId         = google_project.default.project_id
        appId             = module.firebase.app.app_id
        apiKey            = module.firebase.app_config.api_key
        authDomain        = module.firebase.app_config.auth_domain
        databaseURL       = lookup(module.firebase.app_config, "database_url", "")
        storageBucket     = lookup(module.firebase.app_config, "storage_bucket", "")
        messagingSenderId = lookup(module.firebase.app_config, "messaging_sender_id", "")
        measurementId     = lookup(module.firebase.app_config, "measurement_id", "")
      }
    }
  })
  filename = "${path.module}/secrets.json"
  depends_on = [
    module.firebase
  ]
}

resource "local_file" "firebaserc" {
  content = jsonencode({
    projects = {
      development = google_project.default.project_id
      production  = google_project.default.project_id
    }
  })
  filename = "${path.module}/.firebaserc"
  depends_on = [
    google_project.default
  ]
}


resource "local_file" "admin_config" {
  content  = base64decode(google_service_account_key.sa_key.private_key)
  filename = "${path.module}/admin-config.json"
  depends_on = [
    google_service_account_key.sa_key,
    module.firebase
  ]
}
