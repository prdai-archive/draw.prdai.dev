locals {
  name = var.project
  tags = {
    Project   = var.project
    ManagedBy = "terraform"
  }
}
