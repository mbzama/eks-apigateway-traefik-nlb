# ─────────────────────────────────────────────────────────────────────────────
# AWS Provider
# ─────────────────────────────────────────────────────────────────────────────
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.cluster_name
      ManagedBy   = "terraform"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Data sources – resolved after EKS cluster is created
# ─────────────────────────────────────────────────────────────────────────────
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes Provider
# Configured with the EKS cluster endpoint and auth token.
#
# NOTE: On a brand-new workspace run `terraform apply -target=aws_eks_cluster.main`
# first so that these values are available for subsequent applies.
# ─────────────────────────────────────────────────────────────────────────────
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# ─────────────────────────────────────────────────────────────────────────────
# Helm Provider
# ─────────────────────────────────────────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}
