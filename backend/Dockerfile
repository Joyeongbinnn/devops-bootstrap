# 1) Build
FROM gradle:8.10-jdk17-alpine AS builder
WORKDIR /workspace

# gradle 설정/래퍼 복사
COPY build.gradle settings.gradle gradlew ./
RUN chmod +x gradlew
COPY gradle ./gradle

# 래퍼 동작 확인
RUN ./gradlew --version

# 소스 복사 후 빌드
COPY src ./src
RUN ./gradlew clean build -x test

# ★ bootJar만 임시 위치로 복사(plain 제외)
#   - build/libs 안에서 'plain'이 아닌 첫 번째 jar를 /tmp/app.jar 로 복사
RUN set -eux; \
    JAR_FILE="$(ls build/libs/*.jar | grep -v 'plain' | head -n 1)"; \
    cp "$JAR_FILE" /tmp/app.jar

# 2) Run
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
ENV JAVA_OPTS=""

# 위에서 선별한 단일 JAR만 복사 → 목적지가 파일이어도 OK
COPY --from=builder /tmp/app.jar /app/app.jar

EXPOSE 8080
ENTRYPOINT ["sh","-c","java $JAVA_OPTS -jar /app/app.jar"]
