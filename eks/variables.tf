variable "access_key" {
  type      = string
  sensitive = true
}

variable "secret_key" {
  type      = string
  sensitive = true
}

variable "aws-region" {
  type    = string
  default = "us-east-1"
}

variable "region" {
  type    = string
  default = "us-east-1"
}