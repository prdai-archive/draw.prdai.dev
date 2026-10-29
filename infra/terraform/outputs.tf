output "app_url" {
  description = "Public URL served through Cloudflare."
  value       = "https://${var.app_hostname}"
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Elastic IP attached to the instance."
  value       = aws_eip.app.public_ip
}

output "ssm_session_command" {
  description = "Shell access without opening port 22."
  value       = "aws ssm start-session --target ${aws_instance.app.id} --region ${var.aws_region}"
}

output "backups_path" {
  description = "Pre-deploy backups on the instance data volume."
  value       = "/opt/excalidash/backups"
}

output "github_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN repository variable for the deploy workflow."
  value       = aws_iam_role.github_deploy.arn
}
