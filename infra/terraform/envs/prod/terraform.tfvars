# (1) AWS 계정/리전 예시
aws_account_id = "111122223333"   # 예시
aws_region     = "ap-northeast-2" # 예시(서울)

# (2) Route53 호스티드존/도메인 예시
domain         = "soboro.com"     # 예시
hosted_zone_id = "Z123EXAMPLE45"  # 예시

# (3) ECR 리포지토리 예시
ecr_repo_backend  = "soboro/backend"   # 예시
ecr_repo_frontend = "soboro/frontend"  # 예시

# (4) Git 리포지토리(더미 URL)
git_repo_url  = "https://example.com/your/repo.git"
git_main_branch = "main"

# (5) 서브도메인(아래 README의 사용가능 목록에서 선택/변경)
subdomain_jenkins = "jenkins"
subdomain_argocd  = "argocd"
subdomain_grafana = "grafana"

# (6) 초기 관리자/인증 이메일(예시)
letsencrypt_email = "admin@soboro.com" # 예시
grafana_admin_pass = "ChangeMe-Admin!" # 예시

# EC2 스펙(예시)
ec2_key_name = "soboro-key"      # 예시
ci_instance_type      = "t3.large"
k3s_master_type       = "t3.large"
k3s_worker_type       = "t3.large"
k3s_worker_count      = 2
