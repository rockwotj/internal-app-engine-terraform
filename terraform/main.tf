
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.20.0"
    }
  }
  # backend "gcs" {
  # Can't use the variable that contains the bucket name here.
  #  bucket = ""
  #  prefix = ""
  # }
}

provider "google" {
  project = var.project_name
  region  = "us-central1"
}

resource "google_storage_bucket" "terraform_state" {
  name          = "${var.project_name}-terraform-tfstate"
  force_destroy = false
  location      = "US"
  storage_class = "STANDARD"
  versioning {
    enabled = true
  }
}

### Identity Aware Proxy Configuration ###

resource "google_project_service" "project_service" {
  project = var.project_name
  service = "iap.googleapis.com"
}

resource "google_iap_brand" "internal_brand" {
  support_email     = "admin@corp.com"
  application_title = "Internal IAP Protected Application"
  project           = google_project_service.project_service.project
}

resource "google_iap_client" "internal_client" {
  display_name = "Internal Client"
  brand        =  google_iap_brand.internal_brand.name
}

data "google_iam_policy" "my_team" {
  binding {
    role = "roles/iap.httpsResourceAccessor"
    members = [
      "group:my-team@corp.com",
    ]
  }
}

# Make it so only my_team members can access this app
resource "google_iap_web_type_app_engine_iam_policy" "policy" {
  project = var.project_name
  app_id = google_app_engine_application.internal_app.app_id
  policy_data = data.google_iam_policy.my_team.policy_data
}

### App Engine Configuration ###

resource "google_app_engine_application" "internal_app" {
  project     = var.project_name
  location_id = "us-central"

  # This is when using app engine user API
  # unless you're storing per user info you don't need that
  # IAP will handle everything for you.
  auth_domain = "redpanda.com"
  iap {
    enabled = true
    oauth2_client_id = google_iap_client.internal_client.client_id
    oauth2_client_secret = google_iap_client.internal_client.secret
  }
}

### Bucket for deployment ###

resource "google_storage_bucket" "app" {
  name          = "${var.project_name}-${random_id.app.hex}"
  location      = "US"
  force_destroy = true
  versioning {
    enabled = true
  }
}

resource "random_id" "app" {
  byte_length = 8
}

### App Engine `hello_app` Deployment & Configuration ###

data "archive_file" "hello_app_dist" {
  type        = "zip"
  source_dir  = "../hello_app/"
  output_path = "../hello_app/hello_app.zip"
}

resource "google_storage_bucket_object" "hello_app" {
  name   = "hello_app.zip"
  source = data.archive_file.hello_app_dist.output_path
  bucket = google_storage_bucket.app.name
}

resource "google_app_engine_standard_app_version" "hello_app" {
  version_id = var.deployment_version
  service    = "${var.hello_app_service_name}"
  runtime    = "nodejs20"

  entrypoint {
    shell = "node dist/index.js"
  }

  deployment {
    zip {
      source_url = "https://storage.googleapis.com/${google_storage_bucket.app.name}/${google_storage_bucket_object.hello_app.name}"
    }
  }

  # https://cloud.google.com/appengine/docs/standard
  instance_class = "F1"

  automatic_scaling {
    max_concurrent_requests = 10
    min_idle_instances      = 0
    max_idle_instances      = 3
    min_pending_latency     = "1s"
    max_pending_latency     = "5s"
    standard_scheduler_settings {
      target_cpu_utilization        = 0.5
      target_throughput_utilization = 0.75
      min_instances                 = 0
      max_instances                 = 3
    }
  }
  noop_on_destroy = true
  delete_service_on_destroy = true
}

resource "google_app_engine_application_url_dispatch_rules" "internal_apps_dispatch_rules" {
  dispatch_rules {
    domain = "*"
    path = "/*"
    service = "${var.hello_app_service_name}"
  }
}

# Always send all traffic to the latest version
resource "google_app_engine_service_split_traffic" "hello_app" {
  service = google_app_engine_standard_app_version.hello_app.service
  migrate_traffic = false
  split {
    shard_by = "RANDOM"
    allocations = {
      (google_app_engine_standard_app_version.hello_app.version_id) = 1
    }
  }
}
