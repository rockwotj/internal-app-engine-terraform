variable "project_name" {
  type = string
  default = ""
}

variable "hello_app_service_name" {
  type = string
  # The first service must be called default
  default = "default"
}

variable "deployment_version" {
  type = string
  default = ""
}
