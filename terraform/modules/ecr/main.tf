resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "null_resource" "this" {
  triggers = {
    ecr_repo_url = aws_ecr_repository.this.repository_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${var.aws_region} \
        | docker login --username AWS --password-stdin ${aws_ecr_repository.this.registry_id}.dkr.ecr.${var.aws_region}.amazonaws.com

      docker pull public.ecr.aws/lambda/java:25
      docker tag  public.ecr.aws/lambda/java:25 ${aws_ecr_repository.this.repository_url}:latest
      docker push ${aws_ecr_repository.this.repository_url}:latest
    EOT
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.keep_image_count} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_image_count
      }
      action = { type = "expire" }
    }]
  })
}
