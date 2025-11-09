terraform {
  backend "s3" {
    bucket         = "soboro-tfstate-example"    # 실제 S3 버킷명으로 변경
    key            = "prod/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "soboro-tfstate-lock"       # 실제 DDB 테이블명으로 변경
    encrypt        = true
  }
}
