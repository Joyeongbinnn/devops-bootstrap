variable "aws_account_id"  { type = string }
variable "aws_region"      { type = string }

variable "domain"          { type = string }
variable "hosted_zone_id"  { type = string }

variable "ecr_repo_backend"  { type = string }
variable "ecr_repo_frontend" { type = string }

variable "git_repo_url"      { type = string }
variable "git_main_branch"   { type = string }

variable "subdomain_jenkins" { type = string }
variable "subdomain_argocd"  { type = string }
variable "subdomain_grafana" { type = string }

variable "letsencrypt_email" { type = string }
variable "grafana_admin_pass"{ type = string }

variable "ec2_key_name"      { type = string }
variable "ci_instance_type"  { type = string }
variable "k3s_master_type"   { type = string }
variable "k3s_worker_type"   { type = string }
variable "k3s_worker_count"  { type = number }
