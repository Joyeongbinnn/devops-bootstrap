# Soboro IaC & GitOps 템플릿 (infra 폴더)

이 문서는 `infra/` 폴더의 구성, 아키텍처(설계도), 그리고 이 인프라를 로컬・클라우드 환경에서 배포/검증하는 단계별 가이드를 제공합니다.

요약: 이 레포는 k3s 기반 클러스터 부트스트랩 스크립트, Terraform(네트워크/레코드/클러스터 인프라), CI(로컬 Docker Compose로 Jenkins), GitOps(ArgoCD) 및 모니터링 스택(kube-prometheus-stack) 예시를 포함합니다.

목표 독자: 인프라 엔지니어, DevOps 엔지니어, 또는 로컬/프로덕션 k3s + ArgoCD 기반 GitOps 파이프라인을 이해/실행하려는 개발자

---

## 목차

- 개요 및 아키텍처 다이어그램
- 폴더 구조와 주요 파일 설명
- 준비물 (사전 요구사항)
- 단계별 실행 가이드
  - k3s 부트스트랩 (master/worker 스크립트)
  - Terraform으로 인프라 생성 (Route53, DNS, S3 등)
  - CI (infra/CI/docker-compose.yaml) — 로컬 테스트용 Jenkins
  - 컨테이너 빌드/푸시 (ECR 등)
  - ArgoCD 적용 및 앱 배포 (infra/k8s/20-argocd/apps)
  - 모니터링 스택 적용
- 시크릿과 민감정보 관리 권장사항
- 검증 및 트러블슈팅
- 추가 개선 아이디어

---

## 1) 아키텍처 개요 (설계도)

요구사항 반영: k3s용 EC2는 별도의 풀에서 3대(클러스터 노드 3대), CI(Jenkins)는 별도의 EC2 1대에서 운영합니다. 모든 서비스는 서브도메인으로 분리합니다 (예: `argocd.example.com`, `jenkins.example.com`, `grafana.example.com`, 앱별 도메인).

아래 ASCII 다이어그램은 분리된 인프라를 단순화하여 보여줍니다.

```
  +--------------------+            +----------------------+
  | Developer / CI     |  push     | Git Repository (this) |
  | - push manifests   |---------> | - manifests for Argo  |
  | - push images      |           +----------------------+
  +---------+----------+
            |
            | (Docker images)
            v
  +--------------------+     Terraform    +--------------------+
  | Registry (ECR)     | <-------------- | AWS infra (Route53,|
  +--------------------+                  |  DNS, S3 backend)  |
                                             +--------------------+

  +----------------------+    +---------------------+
  | k3s cluster (3 EC2)  |    | CI EC2 (Jenkins)    |
  |  - argocd            |    |  - docker-compose   |
  |  - apps (40-app/*)   |    |  - image builds     |
  |  - monitoring        |    |  - kaniko/kanikoctl |
  +----------------------+    +---------------------+

  External: Route53 + cert-manager (DNS-01) -> TLS certs for Ingress hosts
```

설명 요약:

- Terraform: DNS 레코드, TLS 발급용 Route53 세팅(ClusterIssuer), S3/State 등
- k3s: 로컬/VM 환경에서 간편하게 테스트 가능한 스크립트(`infra/script/`)
- ArgoCD: Git 리포지터리에 저장된 앱 선언을 읽어 K8s에 배포
- CI: `infra/CI/docker-compose.yaml`은 로컬에서 Jenkins를 띄워 Kaniko/빌드 테스트 등을 검증하기 위한 샘플
- Monitoring: `infra/k8s/21-monitoring/kube-prometheus-stack`로 커스터마이징 가능

---

## 2) 폴더 구조 & 주요 파일

- `infra/terraform/` - 클라우드 리소스 (Route53, S3 백엔드 등) 및 환경별 tfvars
  - `envs/prod/terraform.tfvars` - 실제로 수정해야 하는 값(도메인/계정/리포 등)
- `infra/script/` - k3s 클러스터 부트스트랩 스크립트
  - `bootstrap-k3s-master.sh`, `bootstrap-k3s-worker.sh`
- `infra/CI/` - 로컬 CI 검증용 docker-compose (Jenkins, reverse proxy 등)
  - `.env.example`, `docker-compose.yaml`, `nginx.conf`, `jenkins/Dockerfile`
- `infra/k8s/` - 클러스터 내 리소스 매니페스트
  - `00-namespaces.yaml` - 네임스페이스
  - `11-cluster-issuer-route53.yaml` - cert-manager ClusterIssuer (Route53)
  - `20-argocd/` - ArgoCD Ingress 및 앱 정의(backend, frontend)
  - `21-monitoring/` - kube-prometheus-stack 설정값
  - `40-app/` - 실제 앱의 k8s 매니페스트(backend, frontend)

---

## 3) 사전 준비물

- 로컬: `bash`/WSL 또는 Linux 환경 권장 (k3s bootstrap 스크립트는 bash 기반)
- AWS 계정 및 Route53 Hosted Zone (도메인)
- Terraform 설치(>= 1.x 권장)
- kubectl 설치
- (옵션) Docker, docker-compose (CI 로컬 실행용)
- AWS CLI 또는 적절한 IAM 키 (Terraform/CI에서 사용)

윈도우 PowerShell 사용 시: 긴 bash 스크립트를 실행해야 하면 WSL 사용 권장. README 내에 PowerShell에 맞춘 몇 개 명령도 함께 제공합니다。

추가 요구사항 (Jenkins/CI):
- Jenkins(또는 CI 시스템)는 `AWS_REGION` 및 `ECR_ACCOUNT_ID` 환경변수를 반드시 제공해야 합니다. Jenkinsfile은 레포에 하드코딩된 계정/리전을 사용하지 않으며, 파이프라인 시작 시 해당 값들을 검증합니다.

Grafana 비밀번호 취급: `infra/k8s/21-monitoring/kube-prom-stack-values.yaml`에서 기본 adminPassword는 제거했습니다. Grafana 관리자 비밀번호는 클러스터 내 `Secret`으로 생성하여 사용하세요. 예:

```bash
kubectl -n monitoring create secret generic grafana-admin --from-literal=admin-password='<secure-password>'
```

---

## 4) 단계별 실행 가이드 (핵심)

아래 가이드는 일반적인 흐름입니다. 환경(로컬/프로덕션)에 따라 조정하세요。

### A — 필수 변수 수정 (k3s 3대, CI 1대 구조 반영)

편집: `infra/terraform/envs/prod/terraform.tfvars`

- `aws_account_id`, `aws_region`, `domain`, `hosted_zone_id`
- `ecr_repo_backend`, `ecr_repo_frontend`, `git_repo_url`, `git_main_branch`
- `subdomain_jenkins`, `subdomain_argocd`, `subdomain_grafana`, `subdomain_apps` (앱 노출용)
- `letsencrypt_email`, `grafana_admin_pass` (운영 시 안전하게 보관)

k3s 노드 수 설정: 이 레포의 Terraform 변수는 `k3s_worker_count`(워커 수)를 사용합니다. 현재 스크립트/모듈은 마스터 1대 + `k3s_worker_count` 워커로 동작합니다.

- 원하는 총 k3s EC2 수가 3대(예: 1 master + 2 workers)라면 `k3s_worker_count = 2`로 설정하세요.
- CI 전용 EC2는 Terraform에서 `ci_instance_type` 및 관련 자원으로 관리됩니다(예: 하나의 EC2에 Jenkins를 띄움).

항상 민감값은 Git에 평문 커밋하지 마세요。

### B — Terraform으로 인프라 생성

PowerShell / bash 공통:

```powershell
cd infra/terraform
terraform init
terraform plan -var-file=envs/prod/terraform.tfvars
terraform apply -var-file=envs/prod/terraform.tfvars -auto-approve
```

설명: 이 단계는 DNS 레코드, 필요한 IAM/리소스, 그리고 (구성된 경우) ECR, S3 backend 등을 생성합니다。

### C — k3s 부트스트랩 (EC2에서 실행)

설정에 따라 EC2 3대를 준비합니다. Terraform에서 인스턴스를 만들었다면 다음 정책을 따르세요:

- 마스터 노드(1대): `infra/script/bootstrap-k3s-master.sh`를 실행하여 k3s server로 설정합니다.
- 워커 노드(2대): 각 워커에서 `infra/script/bootstrap-k3s-worker.sh <MASTER_IP>`를 실행해 클러스터에 조인합니다.

예 (마스터에서):

```bash
# 마스터에서 (bash)
sudo bash infra/script/bootstrap-k3s-master.sh

# 각 워커에서 (bash)
sudo bash infra/script/bootstrap-k3s-worker.sh <MASTER_IP>
```

검증:

```bash
kubectl get nodes
kubectl get ns
```

참고: `k3s_worker_count` 값을 Terraform에서 2로 설정하면(마스터 1대 + 워커 2대) 총 3대 k3s 클러스터가 구성됩니다.

### D — ArgoCD 설치 및 GitOps 연결

레포의 `infra/k8s/20-argocd/`는 ArgoCD 노출용 Ingress와 apps 디렉터리를 포함합니다。 일반 흐름:

1. ArgoCD를 설치 (공식 매니페스트 또는 Helm)
2. `ing-argocd.yaml`을 수정해 호스트명(예: `argocd.YOURDOMAIN`) 반영
3. `apps/backend.yaml`, `apps/frontend.yaml`, `apps/project.yaml`을 통해 Git 리포의 앱을 가리키도록 설정

ArgoCD에 접속 후 앱 상태 확인 및 동기화：

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# 브라우저에서 https://localhost:8080 접속
```

### E — CI (별도 EC2에서 운영)

요구에 따라 CI(Jenkins)는 별도 EC2 1대에 설치합니다. Terraform에서 `ci_instance_type`을 설정한 뒤 EC2에 접속하여 `infra/CI/`를 배포하세요.

간단 배포 (CI EC2 접속 후):

```bash
cd /path/to/repo/infra/CI
docker-compose up -d
```

PowerShell을 사용 중이고 CI EC2를 원격에서 관리하려면 SSH로 접속한 뒤 위 명령을 실행하세요. CI용 EC2는 외부(인터넷) 접근이 필요하므로 보안 그룹에서 HTTP/HTTPS/SSH 규칙을 적절히 설정하십시오.

도메인 분리: Jenkins는 Terraform에서 설정한 `subdomain_jenkins` (예: `jenkins.example.com`)으로 노출하고, k3s Ingress는 앱/argocd/grafana용 서브도메인으로 분리하세요.

CI와 k3s 노드의 네트워크 분리는 보안 및 리소스 격리에 유리합니다. 빌드 중 큰 리소스/IO를 CI 인스턴스로 격리하면 k3s 워크로드에 영향이 적습니다。

### F — 앱 빌드 & 이미지 푸시 (ECR 예시)

로컬에서 Docker로 빌드하고 ECR로 푸시하는 일반적인 예(권한 및 리포는 terraform.tfvars에 설정됨)：

```powershell
# Docker 로그인 (ECR 사용 예)
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com

# backend 빌드/태그/푸시
docker build -t backend:local ..\\backend
docker tag backend:local <account>.dkr.ecr.<region>.amazonaws.com/<ecr_repo_backend>:v1
docker push <account>.dkr.ecr.<region>.amazonaws.com/<ecr_repo_backend>:v1

# frontend 유사
```

대안: 로컬 Jenkins/Kaniko를 통해 빌드 자동화。

### G — ArgoCD가 앱을 동기화하면 애플리케이션이 배포됩니다

ArgoCD에서 앱을 수동 또는 자동 동기화하여 배포 상태를 확인하세요。

```bash
kubectl get deployments -n <app-namespace>
kubectl get svc -n <app-namespace>
```

### H — 모니터링

모니터링 설정은 `infra/k8s/21-monitoring/kube-prom-stack-values.yaml`에 있습니다。 이 값을 Helm으로 적용하거나 ArgoCD 앱으로 관리하세요。

예: Helm (로컬 시)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -f infra/k8s/21-monitoring/kube-prom-stack-values.yaml -n monitoring --create-namespace
```

---

## 5) 시크릿/민감정보 관리 권장사항

- Git에 평문 커밋 금지
- K8s Secret 대신 SealedSecret, Sops, HashiCorp Vault, 또는 SSM/Parameter Store 사용 권장
- `infra/k8s/40-app/*/secret.env.example` 파일은 샘플입니다。 운영시 별도 시크릿 매커니즘으로 교체하세요。

---

## 6) 검증 & 트러블슈팅

- 클러스터가 준비되었는지: `kubectl get nodes`, `kubectl get pods -A`
- ArgoCD 앱 상태: ArgoCD UI 또는 `kubectl -n argocd get applications`
- TLS 문제: cert-manager 로그(`kubectl logs -n cert-manager <pod>`), Route53 권한 확인
- Jenkins/CI: `docker-compose logs jenkins` (infra/CI)
- Terraform: `terraform plan`/`apply` 실패 시 AWS 권한、 hosted zone id、 및 변수 값을 다시 확인

문제가 지속되면 README 하단의 “자주 발생하는 오류”를 참고하거나 이 리포의 이슈로 상세 로그와 함께 문의 바랍니다。

---

## 7) 추가 개선 / 다음 단계 (권장)

- GitHub Actions/GitLab CI로 Terraform 자동화、PR 검증 파이프라인 도입
- 이미지 스캔(CVE) 및 SBOM 생성
- 자동화된 테스트(통합/엔드투엔드) 파이프라인 추가
- Secrets 매니지먼트 통합(Vault or Sops)

---

## 변경 사항 요약

- 이 파일은 `infra/` 하위에 있는 리소스들의 구조와 실행 절차를 한 곳에 정리합니다。

---

궁금한 점이나、 특정 환경(예: GCP、 Azure、 완전 매니지드 K8s)에 맞춰 변환을 원하면 알려주세요。 필요한 경우 자동화된 스크립트나 추가 문서(예: QuickStart)를 더 만들어 드리겠습니다。

# Soboro IaC & GitOps 템플릿

이 템플릿은 **Jenkins–Kaniko–ECR–ArgoCD–k3s** 파이프라인과 **Prometheus+Grafana** 모니터링을
"도메인/계정만 바꾸면" 자동 배포되게 만들어 둔 예시입니다.

> **서브도메인 권장**: `jenkins`, `argocd`, `grafana` (이유: 서브패스 대비 쿠키/링크/리라이트 이슈가 적어 운영이 안정적)  
> ArgoCD 설치/노출: 공식 매니페스트 + 호스트형 Ingress (argocd.soboro.com).  
> cert-manager Route53 DNS-01 ClusterIssuer 사용.  
> 참고: cert-manager Route53, ArgoCD 설치, kube-prometheus-stack 운영 사례. 〔문서 링크는 대화 상단 참조〕

---

## 0) 준비물

- AWS 계정, Route53 Hosted Zone, 도메인 보유
- Terraform 실행 권한, AWS CLI 자격 구성(`aws configure`)
- EC2 키페어 이름

## 1) **반드시 실제로 고칠 곳** (예시/더미 제거)

편집 파일: `infra/terraform/envs/prod/terraform.tfvars`

- (1) **AWS 계정/리전**: `aws_account_id`, `aws_region` — _현재 예시값_
- (2) **Route53**: `domain`, `hosted_zone_id` — _현재 예시값_
- (3) **ECR 리포**: `ecr_repo_backend`, `ecr_repo_frontend` — _현재 예시값_
- (4) **Git 리포/브랜치**: `git_repo_url`, `git_main_branch` — _현재 더미 URL_
- (5) **서브도메인 (사용가능 목록)**:
  - `jenkins`, `ci`, `build` 중 택1 → `subdomain_jenkins`
  - `argocd`, `cd`, `gitops` 중 택1 → `subdomain_argocd`
  - `grafana`, `monitor`, `dash` 중 택1 → `subdomain_grafana`  
    선택 후 `terraform.tfvars`에서 반영.
- (6) **이메일/초기패스워드(예시)**:
  - `letsencrypt_email`(예: ops@YOURDOMAIN) — 현재 예시
  - `grafana_admin_pass` — 현재 예시 (운영 시 즉시 변경)

> **앱 환경변수**:  
> `infra/k8s/40-app/*/configmap.yaml`는 **예시값**이며, 실제 엔드포인트/DB 정보로 수정.  
> 민감 정보는 `secret.env.example`를 보고 **K8s Secret/SealedSecret/SSM**로 대체하세요.

---

## 2) Terraform

```bash
cd infra/terraform
terraform init
terraform plan -var-file=envs/prod/terraform.tfvars
terraform apply -var-file=envs/prod/terraform.tfvars -auto-approve
```
