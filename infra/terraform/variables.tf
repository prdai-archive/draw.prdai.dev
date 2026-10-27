variable "aws_region" {
  description = "AWS region for the instance, volume, and Elastic IP."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Name prefix and default resource tag."
  type        = string
  default     = "excalidash"
}

variable "instance_type" {
  description = "Arm64 instance type. t4g.nano is the cheapest option that runs the stack with swap."
  type        = string
  default     = "t4g.nano"
}

variable "root_volume_gb" {
  description = "Root EBS volume size in GiB. Holds the OS only; Docker data lives on the data volume."
  type        = number
  default     = 8
}

variable "data_volume_gb" {
  description = "Dedicated Docker data volume size in GiB. Survives instance replacement and terraform destroy."
  type        = number
  default     = 8
}

variable "app_hostname" {
  description = "Public hostname served by Cloudflare, for example draw.example.com."
  type        = string
}

variable "cloudflare_zone" {
  description = "Cloudflare zone that contains app_hostname."
  type        = string
}

variable "basic_auth_username" {
  description = "Username for the Caddy basic-auth gate in front of the app."
  type        = string
  default     = "admin"
}

variable "basic_auth_password" {
  description = "Password for the Caddy basic-auth gate. Stored in Terraform state and EC2 user data."
  type        = string
  sensitive   = true
}

variable "repo_url" {
  description = "Repository cloned on the instance for compose files and the deploy script."
  type        = string
  default     = "https://github.com/prdai-archive/ExcaliDash.git"
}

variable "repo_ref" {
  description = "Branch or tag the instance checks out and redeploys from."
  type        = string
  default     = "main"
}

variable "ssh_public_key" {
  description = "Optional OpenSSH public key registered as an EC2 key pair. Prefer SSM Session Manager."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "IPv4 CIDRs allowed to reach port 22. Empty disables SSH ingress."
  type        = list(string)
  default     = []
}

variable "ssh_allowed_ipv6_cidrs" {
  description = "IPv6 CIDRs allowed to reach port 22. The VPC is IPv4-only, so this stays empty unless IPv6 is added."
  type        = list(string)
  default     = []
}

variable "cloudflare_ipv4_cidrs" {
  description = "Cloudflare IPv4 ranges allowed to reach port 443. Refresh from https://www.cloudflare.com/ips/."
  type        = list(string)
  default = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]
}

variable "cloudflare_ipv6_cidrs" {
  description = "Cloudflare IPv6 ranges allowed to reach port 443. Refresh from https://www.cloudflare.com/ips/."
  type        = list(string)
  default = [
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32",
  ]
}
