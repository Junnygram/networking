variable "env_prefix" {
  description = "Prefix for resources"
  type        = string
}

variable "github_repo" {
  description = "The GitHub repository in the format owner/repo"
  type        = string
  default     = "Junnygram/networking"
}
