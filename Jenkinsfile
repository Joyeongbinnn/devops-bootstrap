pipeline {
  agent any

  environment {
    AWS_REGION     = 'us-east-1'
    ECR_ACCOUNT_ID = '528920766011'
    ECR_REGISTRY   = "${ECR_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

    BACKEND_REPO   = 'agora/backend'
    FRONTEND_REPO  = 'agora/frontend'

    BACKEND_KUSTOMIZE_DIR  = 'infra/k8s/40-app/backend'
    FRONTEND_KUSTOMIZE_DIR = 'infra/k8s/40-app/frontend'

    KANIKO_IMAGE   = 'gcr.io/kaniko-project/executor:v1.24.0'

    JENKINS_CONTAINER_NAME = 'jenkins'
    JENKINS_HOME = '/var/jenkins_home'
    DOCKER_CONFIG = '/var/jenkins_home/.docker'

    TARGET_BRANCH = 'master'

    // 루프 방지 토큰
    SKIP_TOKEN = '[skip-jenkins]'

    // [ADD] Trivy 정책 (임계치 초과 시 실패)
    TRIVY_SEVERITY = 'CRITICAL,HIGH'
    TRIVY_IGNORE_UNFIXED = 'true'     // 고정 버전 없는 취약점은 무시하고 싶을 때 'true'
  }

  options { timestamps(); ansiColor('xterm') }

  stages {

    stage('Guard: skip if self-triggered') {
      steps {
        script {
          sh 'git fetch --all --prune >/dev/null 2>&1 || true'
          def lastAuthor  = sh(returnStdout: true, script: "git log -1 --pretty=%ae").trim()
          def lastSubject = sh(returnStdout: true, script: "git log -1 --pretty=%s").trim()
          echo "Last commit author: ${lastAuthor}"
          echo "Last commit subject: ${lastSubject}"

          if (lastAuthor == 'ci@local' || lastSubject.contains(env.SKIP_TOKEN)) {
            echo "✅ Detected self-trigger (author/subject). Skipping pipeline."
            currentBuild.description = "Skipped (self-trigger)"
            env.SKIP_BUILD = 'true'
          } else {
            env.SKIP_BUILD = 'false'
          }
        }
      }
    }

    stage('Prepare Tag') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        script {
          def ts  = sh(returnStdout: true, script: "date +%Y%m%d%H%M").trim()
          def sha = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
          env.IMAGE_TAG = "${ts}-${sha}"
          echo "IMAGE_TAG = ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Ensure ECR connectivity') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-account2-ecr',
                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          sh '''
            set -euo pipefail
            export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
            export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
            aws configure set default.region "${AWS_REGION}"

            echo "🪪 Verifying AWS identity..."
            aws sts get-caller-identity

            echo "🔐 Testing ECR auth..."
            aws ecr get-login-password --region "${AWS_REGION}" >/dev/null
            echo "✅ ECR token retrieved successfully."
          '''
        }
      }
    }

    stage('Write ECR Docker Config (for Kaniko & Trivy)') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-account2-ecr',
                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          sh '''
            set -euo pipefail
            mkdir -p "${DOCKER_CONFIG}"

            aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
            aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
            aws configure set default.region "${AWS_REGION}"

            PASS="$(aws ecr get-login-password --region "${AWS_REGION}")"
            AUTH="$(printf "AWS:%s" "$PASS" | base64 -w 0)"

            cat > "${DOCKER_CONFIG}/config.json" <<EOF
{
  "auths": {
    "${ECR_REGISTRY}": { "auth": "${AUTH}" }
  },
  "HttpHeaders": { "User-Agent": "kaniko" }
}
EOF

            test -s "${DOCKER_CONFIG}/config.json"
            echo "✅ Wrote ${DOCKER_CONFIG}/config.json for Kaniko & Trivy"
          '''
        }
      }
    }

    // [ADD] ESLint – 프론트 품질체크 (경고 허용: 실패 원하면 --max-warnings=0)
    stage('ESLint (frontend)') {
      when { expression { env.SKIP_BUILD != 'true' && fileExists('frontend/package.json') } }
      steps {
        dir('frontend') {
          sh '''
            set -e
            npm ci
            npx eslint . --ext .js,.jsx,.ts,.tsx || true
            # 실패 원하면 ↓로 바꿔라
            # npx eslint . --ext .js,.jsx,.ts,.tsx --max-warnings=0
          '''
        }
      }
    }

    stage('Sanity Check (paths)') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        sh '''
          set -euo pipefail
          echo "🔎 Sanity check inside Jenkins container volume"

          docker run --rm \
            --volumes-from "${JENKINS_CONTAINER_NAME}" \
            -e WORKSPACE="${WORKSPACE}" \
            -e JENKINS_HOME="${JENKINS_HOME}" \
            -e JOB_NAME="${JOB_NAME}" \
            -e BACKEND_KUSTOMIZE_DIR="${BACKEND_KUSTOMIZE_DIR}" \
            -e FRONTEND_KUSTOMIZE_DIR="${FRONTEND_KUSTOMIZE_DIR}" \
            alpine:3.20 sh -lc '
              echo "[inside] WORKSPACE=$WORKSPACE"
              ls -al "$WORKSPACE"
              ls -al "$WORKSPACE/backend"
              ls -al "$WORKSPACE/frontend"
              test -f "$WORKSPACE/backend/Dockerfile" && echo "[OK] backend/Dockerfile"
              test -f "$WORKSPACE/frontend/Dockerfile" && echo "[OK] frontend/Dockerfile"
              test -f "$WORKSPACE/${BACKEND_KUSTOMIZE_DIR}/kustomization.yaml"  && echo "[OK] backend kustomization.yaml"
              test -f "$WORKSPACE/${FRONTEND_KUSTOMIZE_DIR}/kustomization.yaml" && echo "[OK] frontend kustomization.yaml"
            '
        '''
      }
    }

    stage('Build & Push Backend (Kaniko)') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        sh '''
          set -euo pipefail
          echo "🚀 Kaniko build (backend)"
          docker run --rm \
            --volumes-from "${JENKINS_CONTAINER_NAME}" \
            -e DOCKER_CONFIG="${DOCKER_CONFIG}" \
            ${KANIKO_IMAGE} --verbosity=info \
            --context="${WORKSPACE}/backend" \
            --dockerfile=Dockerfile \
            --destination="${ECR_REGISTRY}/${BACKEND_REPO}:${IMAGE_TAG}" \
            --destination="${ECR_REGISTRY}/${BACKEND_REPO}:latest" \
            --snapshot-mode=redo --single-snapshot
        '''
      }
    }

    stage('Build & Push Frontend (Kaniko)') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        sh '''
          set -euo pipefail
          echo "🚀 Kaniko build (frontend)"
          docker run --rm \
            --volumes-from "${JENKINS_CONTAINER_NAME}" \
            -e DOCKER_CONFIG="${DOCKER_CONFIG}" \
            ${KANIKO_IMAGE} --verbosity=info \
            --context="${WORKSPACE}/frontend" \
            --dockerfile=Dockerfile \
            --destination="${ECR_REGISTRY}/${FRONTEND_REPO}:${IMAGE_TAG}" \
            --destination="${ECR_REGISTRY}/${FRONTEND_REPO}:latest" \
            --snapshot-mode=redo --single-snapshot
        '''
      }
    }

    // [ADD] Trivy – 푸시된 ECR “원격 이미지” 스캔 (임계치 초과 시 실패)
    stage('Trivy Scan (remote ECR images)') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        sh '''
          set -euo pipefail

          if ! command -v trivy >/dev/null 2>&1 ; then
            echo "⬇️ Installing trivy..."
            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
          fi

          export DOCKER_CONFIG="${DOCKER_CONFIG}"

          echo "🔎 Trivy scan: backend"
          trivy image \
            --severity "${TRIVY_SEVERITY}" \
            --exit-code 1 \
            --ignore-unfixed=${TRIVY_IGNORE_UNFIXED} \
            ${ECR_REGISTRY}/${BACKEND_REPO}:${IMAGE_TAG}

          echo "🔎 Trivy scan: frontend"
          trivy image \
            --severity "${TRIVY_SEVERITY}" \
            --exit-code 1 \
            --ignore-unfixed=${TRIVY_IGNORE_UNFIXED} \
            ${ECR_REGISTRY}/${FRONTEND_REPO}:${IMAGE_TAG}

          echo "✅ Trivy passed policy."
        '''
      }
    }

    stage('Update kustomization (set images)') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        sh '''
          set -euo pipefail
          echo "🧱 Update kustomization.yaml with new tags"

          if ! command -v kustomize >/dev/null 2>&1; then
            echo "⬇️ Installing kustomize locally..."
            curl -sL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash
            mv kustomize /usr/local/bin/ || sudo mv kustomize /usr/local/bin/
          fi

          # backend
          cd "${WORKSPACE}/${BACKEND_KUSTOMIZE_DIR}"
          kustomize edit set image \
            ${ECR_REGISTRY}/${BACKEND_REPO}=${ECR_REGISTRY}/${BACKEND_REPO}:${IMAGE_TAG}

          # frontend
          cd "${WORKSPACE}/${FRONTEND_KUSTOMIZE_DIR}"
          kustomize edit set image \
            ${ECR_REGISTRY}/${FRONTEND_REPO}=${ECR_REGISTRY}/${FRONTEND_REPO}:${IMAGE_TAG}

          echo "✅ kustomization updated to tag: ${IMAGE_TAG}"
        '''
      }
    }

    stage('Commit & Push manifest changes') {
      when { expression { env.SKIP_BUILD != 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'gitlab-ssafy',
                          usernameVariable: 'GIT_USER',
                          passwordVariable: 'GIT_PASS')]) {
          sh '''
            set -euo pipefail

            BR="${TARGET_BRANCH}"
            CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
            if [ -n "$CUR" ] && [ "$CUR" != "HEAD" ]; then BR="$CUR"; fi

            git config user.name  "Jenkins CI"
            git config user.email "ci@local"

            git add "${BACKEND_KUSTOMIZE_DIR}/kustomization.yaml" "${FRONTEND_KUSTOMIZE_DIR}/kustomization.yaml" || true

            if ! git diff --cached --quiet; then
              git commit -m "chore(ci): bump images to ${IMAGE_TAG} ${SKIP_TOKEN}"
              ORIGIN_URL="$(git config --get remote.origin.url)"
              REPO_PATH="$(printf '%s' "$ORIGIN_URL" | sed -e 's#^https://##')"

              echo "⬆️ Pushing to ${BR}"
              git push "https://oauth2:${GIT_PASS}@${REPO_PATH}" HEAD:${BR}
              echo "✅ Manifest pushed."
            else
              echo "ℹ️ No manifest changes to commit."
            fi
          '''
        }
      }
    }
  }

  post {
    success {
      script {
        if (env.SKIP_BUILD == 'true') {
          echo "⏭️ Pipeline skipped (self-trigger)."
        } else {
          echo "✅ Push complete"
          echo "Backend:  ${ECR_REGISTRY}/${BACKEND_REPO}:${IMAGE_TAG}"
          echo "Frontend: ${ECR_REGISTRY}/${FRONTEND_REPO}:${IMAGE_TAG}"
          echo "🔁 Kustomize updated & committed. ArgoCD should auto-sync."
        }
      }
    }
    failure {
      echo "❌ Build failed. Check stages above."
    }
  }
}
