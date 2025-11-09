# 배포 가이드 (템플릿)

> 이 문서는 본 레포지토리를 “한 번의 변수값 입력 → 자동 배포” 가능한 템플릿으로 사용하는 방법을 설명합니다.  
> 실제 운영 시엔 아래 값들을 여러분의 환경에 맞게 수정해주세요.

## 1. 환경 정보 (예시)

- AWS 계정 ID : `123456789012`
- AWS 리전 : `ap-northeast-2`
- 도메인 : `soboro.com`
- Hosted Zone ID : `Z0ABCDEF12345`
- EC2 SSH Key Name : `soboro-key`

> 위 값들은 예시입니다. 실제 환경에서는 여러분의 계정/리전/도메인 값을 입력하세요.

## 2. 서브도메인 설정 (예시)

- CI 서버(Jenkins) : `jenkins.soboro.com`
- GitOps 서버(ArgoCD) : `argocd.soboro.com`
- 모니터링(Grafana) : `grafana.soboro.com`

> 도메인 예시입니다. 사용하시려는 서브도메인이 다르다면 변경하세요.

## 3. EC2 인스턴스 사양 (예시)

- CI EC2 : `t3.large`, 50 GiB SSD
- k3s 마스터 EC2 : `t3.large`, 50 GiB SSD
- k3s 워커 EC2 (×2) : 각 `t3.large`, 50 GiB SSD

> 필요에 따라 인스턴스 타입/Disk 용량을 조정하세요.

## 4. Git 저장소 및 브랜치 (예시)

- Git 저장소 URL : `git@github.com:your-org/soboro-repo.git`
- CI 빌드 트리거 브랜치 : `main`

> 아래 선택 가능한 목록 중에서 하나를 골라 사용하거나 자체 저장소/브랜치를 지정하세요.

## 5. 선택 가능한 ECR 리포지토리 이름 목록

- `soboro/backend`
- `soboro/frontend`
- `soboro/app-service`
- `soboro/worker-service`

> 위 목록 중 하나를 선택하거나, 여러분 프로젝트에 맞게 자체 리포지토명을 입력하세요.

## 6. 선택 가능한 모니터링 접근 방식

- **서브도메인 방식** : `grafana.soboro.com` 등으로 독립 도메인 사용
- **경로 기반 방식** : `soboro.com/grafana`, `soboro.com/argocd` 등으로 경로 리라이트 사용
  - 추천: 서브도메인 방식 (세션/쿠키/보안 정책이 분리되어 관리가 쉬움)
  - 경로 기반 방식도 가능하나 리버스프록시 설정 복잡도 및 인증/리다이렉션 이슈 존재

> 위 두 가지 방식 중 하나를 선택하세요. (본 프로젝트는 **서브도메인 방식**을 기본 설정으로 가정하고 있습니다.)

---

### ✅ 배포 순서 요약

1. `infra/terraform/envs/prod/terraform.tfvars` 파일에서 위 변수들(1~6)을 실제 환경 값으로 수정
2. Terraform 실행:
   ```bash
   cd infra/terraform/envs/prod
   terraform init
   terraform apply -auto-approve
   ```
