data "cloudflare_zone" "app" {
  filter = {
    name = var.cloudflare_zone
  }
}

resource "cloudflare_dns_record" "app" {
  zone_id = data.cloudflare_zone.app.id
  name    = var.app_hostname
  type    = "A"
  content = aws_eip.app.public_ip
  proxied = true
  ttl     = 1
  comment = "ExcaliDash origin, managed by Terraform"
}
