locals {
  name_prefix = "soboro"
}

# VPC (간단: 퍼블릭 서브넷 2개)
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${local.name_prefix}-pub-a" }
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = "${var.aws_region}c"
  map_public_ip_on_launch = true
  tags = { Name = "${local.name_prefix}-pub-c" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route { cidr_block = "0.0.0.0/0" gateway_id = aws_internet_gateway.igw.id }
  tags = { Name = "${local.name_prefix}-rt-public" }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# SGs
resource "aws_security_group" "ci" {
  name        = "${local.name_prefix}-ci-sg"
  description = "CI EC2"
  vpc_id      = aws_vpc.main.id

  ingress { from_port = 22  to_port = 22  protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 80  to_port = 80  protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 443 to_port = 443 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0   to_port = 0   protocol = "-1"  cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "${local.name_prefix}-ci-sg" }
}

resource "aws_security_group" "k3s" {
  name        = "${local.name_prefix}-k3s-sg"
  description = "k3s nodes"
  vpc_id      = aws_vpc.main.id

  # SSH & HTTP/HTTPS 공개(초기 단순화)
  ingress { from_port = 22  to_port = 22  protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 80  to_port = 80  protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 443 to_port = 443 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  # k8s/k3s 내부 통신 (예: 6443 API, 8472/UDP flannel, 노드 간 전체 허용 단순화)
  ingress { from_port = 0   to_port = 65535 protocol = "tcp" cidr_blocks = [aws_vpc.main.cidr_block] }
  ingress { from_port = 0   to_port = 65535 protocol = "udp" cidr_blocks = [aws_vpc.main.cidr_block] }
  egress  { from_port = 0   to_port = 0     protocol = "-1"  cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "${local.name_prefix}-k3s-sg" }
}

# IAM (필요권한 최소 예시)
data "aws_iam_policy_document" "ecr_push" {
  statement {
    actions   = ["ecr:*"]
    resources = ["*"]
  }
}
resource "aws_iam_role" "ci_role" {
  name = "${local.name_prefix}-ci-role"
  assume_role_policy = jsonencode({
    Version="2012-10-17", Statement=[{Effect="Allow", Principal={Service="ec2.amazonaws.com"}, Action="sts:AssumeRole"}]
  })
}
resource "aws_iam_role_policy" "ci_ecr" {
  name = "${local.name_prefix}-ci-ecr"
  role = aws_iam_role.ci_role.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# cert-manager Route53 DNS01용(HostedZone 변경권한 - 최소 권한화 권장)
data "aws_iam_policy_document" "certmgr_dns" {
  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.hosted_zone_id}"]
  }
  statement {
    actions   = ["route53:ListHostedZonesByName","route53:ListHostedZones","route53:ListResourceRecordSets"]
    resources = ["*"]
  }
}
resource "aws_iam_role" "certmgr_role" {
  name = "${local.name_prefix}-certmgr-role"
  assume_role_policy = jsonencode({
    Version="2012-10-17", Statement=[{Effect="Allow", Principal={Service="ec2.amazonaws.com"}, Action="sts:AssumeRole"}]
  })
}
resource "aws_iam_role_policy" "certmgr_dns" {
  name   = "${local.name_prefix}-certmgr-dns"
  role   = aws_iam_role.certmgr_role.id
  policy = data.aws_iam_policy_document.certmgr_dns.json
}

# ECR
resource "aws_ecr_repository" "backend" {
  name = var.ecr_repo_backend
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_repository" "frontend" {
  name = var.ecr_repo_frontend
  image_scanning_configuration { scan_on_push = true }
}

# EC2 (CI 1대, k3s 3대)
resource "aws_instance" "ci" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.ci_instance_type
  key_name               = var.ec2_key_name
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.ci.id]
  iam_instance_profile   = aws_iam_instance_profile.ci_profile.name
  tags = { Name = "${local.name_prefix}-ci" }
}
resource "aws_iam_instance_profile" "ci_profile" {
  name = "${local.name_prefix}-ci-profile"
  role = aws_iam_role.ci_role.name
}

# k3s master
resource "aws_instance" "k3s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.k3s_master_type
  key_name               = var.ec2_key_name
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  tags = { Name = "${local.name_prefix}-k3s-master" }
}

# k3s workers
resource "aws_instance" "k3s_worker" {
  count                  = var.k3s_worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.k3s_worker_type
  key_name               = var.ec2_key_name
  subnet_id              = aws_subnet.public_c.id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  tags = { Name = "${local.name_prefix}-k3s-worker-${count.index}" }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter { name = "name" values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"] }
}

# Route53 레코드: jenkins → CI 공인IP / argocd/grafana → k3s master 공인IP(초기)
resource "aws_route53_record" "jenkins" {
  zone_id = var.hosted_zone_id
  name    = "${var.subdomain_jenkins}.${var.domain}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.ci.public_ip]
}
resource "aws_route53_record" "argocd" {
  zone_id = var.hosted_zone_id
  name    = "${var.subdomain_argocd}.${var.domain}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.k3s_master.public_ip]
}
resource "aws_route53_record" "grafana" {
  zone_id = var.hosted_zone_id
  name    = "${var.subdomain_grafana}.${var.domain}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.k3s_master.public_ip]
}

output "ci_public_ip"         { value = aws_instance.ci.public_ip }
output "k3s_master_public_ip" { value = aws_instance.k3s_master.public_ip }
output "jenkins_url" { value = "https://${var.subdomain_jenkins}.${var.domain}" }
output "argocd_url"  { value = "https://${var.subdomain_argocd}.${var.domain}" }
output "grafana_url" { value = "https://${var.subdomain_grafana}.${var.domain}" }
