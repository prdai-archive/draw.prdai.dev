---
title: Deploy ExcaliDash on a single EC2 instance
description: Terraform stack for a cheap EC2 host behind Cloudflare, with weekly upstream sync, image redeploys, and SQLite backups.
---

# Deploy on a single EC2 instance

Terraform provisions a small Arm64 EC2 host in `ap-south-1`, keeps Docker data on
a separate EBS volume, and puts Cloudflare in front. A weekly GitHub Action merges
upstream, and a systemd timer redeploys the published images without touching the
database volume.

## What gets created

| Resource | Detail |
| --- | --- |
| VPC, public subnet, internet gateway | Dedicated `10.42.0.0/16` network, no NAT |
| EC2 instance | `t4g.nano`, Amazon Linux 2023 Arm64, 1 GiB swap |
| Root volume | 8 GiB gp3, replaced with the instance |
| Data volume | 8 GiB gp3 mounted at `/var/lib/docker`, `prevent_destroy` |
| Elastic IP | Cloudflare origin address |
| Security group | 443 from Cloudflare ranges only, SSH closed by default |
| IAM role | `AmazonSSMManagedInstanceCore` for shell access without open ports |
| Cloudflare A record | `draw.prdai.dev`, proxied, points at the Elastic IP |

## Cost

Mumbai list prices, 730 hours per month:

| Item | Monthly |
| --- | --- |
| t4g.nano | $2.04 |
| 16 GiB gp3 (root + data) | $1.46 |
| Public IPv4 | $3.65 |
| Cloudflare proxy | $0.00 |
| **Total** | **$7.15** |

No EC2 free tier applies to a paid-plan account. Check remaining credits with
`aws freetier get-account-plan-state`.

## Prerequisites

- Terraform 1.10 or newer.
- AWS credentials for a non-root identity with EC2, EIP, IAM, and VPC permissions.
- A Cloudflare API token scoped to `prdai.dev` with `Zone:Read` and `DNS:Edit`.
- The Cloudflare origin certificate material described below.

## Configure

```sh
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`: region, hostname, zone, and optional SSH CIDRs. The
Cloudflare token comes from the environment, never from a file in the repo.

```sh
export AWS_PROFILE=<profile>
export CLOUDFLARE_API_TOKEN=<token>
terraform init
terraform plan
terraform apply
```

The first boot installs Docker, mounts the data volume, creates `.env` with
generated `JWT_SECRET` and `CSRF_SECRET`, and enables the deploy timer. The stack
does not start until the origin certificate exists.

## Cloudflare origin certificate

1. In the Cloudflare dashboard open `SSL/TLS` -> `Origin Server` -> `Create Certificate`.
2. Cover `draw.prdai.dev`, choose 15 years, and copy both the certificate and key.
3. Write them to the instance:

```sh
aws ssm start-session --target <instance-id> --region ap-south-1
sudo install -d -m 0755 /etc/caddy/certs
sudo tee /etc/caddy/certs/origin.pem >/dev/null
sudo tee /etc/caddy/certs/origin.key >/dev/null
sudo chmod 600 /etc/caddy/certs/origin.key
sudo systemctl start excalidash-deploy
```

4. Set `SSL/TLS` -> `Overview` to `Full (strict)` and enable `Always Use HTTPS`.
5. Open `https://draw.prdai.dev` and create the administrator account.

Terraform creates the proxied A record. SSL mode and Always Use HTTPS stay manual
so the deploy token only needs DNS permissions.

## Access control

Caddy puts HTTP basic auth in front of the whole site. `basic_auth_username`
defaults to `admin`; `basic_auth_password` is required and must be set in
`terraform.tfvars`. The app keeps its own first-run admin onboarding behind that
gate, so the setup code from the backend log is still needed once.

The basic-auth hash is generated on first boot and stored in `/opt/excalidash/.env`.
Rotating the password means updating those two lines and restarting the stack.
This gate is a convenience lock, not a security boundary: the password also lands
in EC2 user data, readable by anyone with `ec2:DescribeInstanceAttribute`.

## Weekly automation

| Job | When | Failure behavior |
| --- | --- | --- |
| `sync-upstream` workflow | Monday 02:00 UTC | Merge conflicts abort the run and push nothing |
| `excalidash-deploy` timer | Monday 03:30 UTC | Health check fails the unit and keeps the previous containers |

The workflow merges `ZimengXiong/ExcaliDash` `main` into the fork. The fork keeps
its `infra/` and `docs/` additions, so the merge stays clean unless upstream edits
the same lines.

The timer is a separate concern from the source sync. Deployed code tracks the
published `zimengxiong/excalidash-*` images, not the fork checkout:

```sh
sudo systemctl list-timers excalidash-deploy.timer
sudo systemctl start excalidash-deploy
journalctl -u excalidash-deploy -n 100 --no-pager
```

Each run stops the backend, archives the `excalidash_backend-data` volume to
`/opt/excalidash/backups/predeploy-<stamp>.tgz`, pulls images, starts the stack,
waits for `/api/health`, and keeps the last four archives. To pin a release instead
of `latest`, set `EXCALIDASH_TAG` in `/opt/excalidash/.env`.

## Storage rules

- The SQLite database, uploads, and generated secrets live on the data EBS volume.
- `terraform destroy` fails while the data volume exists. That is intentional.
- Never run `docker compose down --volumes`. The deploy script only runs `up -d`.
- Instance replacement reattaches the data volume; no data is lost.

## Restore a backup

```sh
sudo systemctl stop excalidash-deploy.timer
cd /opt/excalidash
sudo docker compose -f docker-compose.prod.yml -f infra/ec2/compose.override.yml stop backend
sudo docker run --rm \
  -v excalidash_backend-data:/data \
  -v /opt/excalidash/backups:/backup \
  alpine:3.24 sh -c 'rm -rf /data/* && tar xzf /backup/predeploy-<stamp>.tgz -C /data'
sudo docker compose -f docker-compose.prod.yml -f infra/ec2/compose.override.yml up -d
sudo systemctl start excalidash-deploy.timer
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Cloudflare 522 | Security group allows the current Cloudflare ranges; Caddy is running |
| Caddy exits on boot | Both `origin.pem` and `origin.key` exist in `/etc/caddy/certs` |
| Sync workflow cannot push | Repository settings -> Actions -> Workflow permissions -> Read and write |
| Collaboration drops | `TRUST_PROXY=3` matches Cloudflare, Caddy, and nginx; WebSocket upgrades reach `/socket.io/` |
| Out of memory | `free -m`, `dmesg -T | tail`; swap lives on the root volume |
