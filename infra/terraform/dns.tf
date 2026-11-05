data "cloudflare_zone" "app" {
  count = var.manage_dns ? 1 : 0

  filter = {
    name = var.cloudflare_zone
  }
}

resource "cloudflare_dns_record" "app" {
  count = var.manage_dns ? 1 : 0

  zone_id = data.cloudflare_zone.app[0].id
  name    = var.app_hostname
  type    = "A"
  content = aws_eip.app.public_ip
  proxied = true
  ttl     = 1
  comment = "ExcaliDash origin, managed by Terraform"
}
