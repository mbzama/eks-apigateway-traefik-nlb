# ─────────────────────────────────────────────────────────────────────────────
# ECR Repository  –  stores the NestJS mock-api container image
#
# After `terraform apply` creates this repository, build and push the image:
#
#   aws ecr get-login-password --region us-east-1 \
#     | docker login --username AWS --password-stdin \
#       $(terraform output -raw ecr_repository_url | cut -d/ -f1)
#
#   docker build -t mock-api ../api
#
#   docker tag mock-api:latest $(terraform output -raw ecr_repository_url):latest
#
#   docker push $(terraform output -raw ecr_repository_url):latest
#
# Then update app_image in terraform.tfvars and re-run terraform apply.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_ecr_repository" "mock_api" {
  name                 = "mock-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "mock-api"
  }
}

# Expire untagged images after 30 days to control storage costs
resource "aws_ecr_lifecycle_policy" "mock_api" {
  repository = aws_ecr_repository.mock_api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images older than 30 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}
