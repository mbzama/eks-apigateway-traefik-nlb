# ─────────────────────────────────────────────────────────────────────────────
# IAM – EKS Control Plane Role
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.cluster_name}-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Cluster
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = concat(
      aws_subnet.private[*].id,
      aws_subnet.public[*].id
    )
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    # Public access allows Terraform (running outside the VPC) to communicate
    # with the API server. Restrict source CIDRs in production.
    endpoint_public_access = true
  }

  # Enable control plane logging (useful for debugging)
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = {
    Name = var.cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# OIDC Provider  (enables IAM Roles for Service Accounts – IRSA)
# Required for fine-grained IAM permissions on pods (e.g. AWS Load Balancer
# Controller, External DNS, etc.)
# ─────────────────────────────────────────────────────────────────────────────
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.cluster_name}-oidc-provider"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM – Node Group Role
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.cluster_name}-node-role"
  }
}

# Core worker node permissions
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

# Allows the VPC CNI plugin to manage ENIs (required for pod networking)
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

# Allows nodes to pull images from ECR (required for system pods like aws-node, kube-proxy)
resource "aws_iam_role_policy_attachment" "eks_ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}


# ─────────────────────────────────────────────────────────────────────────────
# Launch Template – attaches the custom node SG and configures disk size.
# disk_size must be set here (not on aws_eks_node_group) when using a
# launch template — the two are mutually exclusive.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.cluster_name}-node-lt-"

  # Attach both security groups:
  # 1. eks_cluster.main cluster_security_group_id – the EKS-managed SG that
  #    enables control-plane ↔ node communication (kubelet, etc.). When using
  #    a launch template, EKS no longer attaches this automatically, so we
  #    must include it explicitly or nodes fail to join the cluster.
  # 2. eks_nodes – our custom SG with the additional ingress rules.
  vpc_security_group_ids = [
    aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
    aws_security_group.eks_nodes.id,
  ]

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-node"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Managed Node Group
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # Workers run in private subnets – traffic to/from internet goes through NAT
  subnet_ids = aws_subnet.private[*].id

  instance_types = [var.node_instance_type]
  # disk_size is omitted here – configured in the launch template above.
  # Setting disk_size directly on the node group conflicts with launch_template.

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # max_unavailable_percentage avoids a deadlock when max_size == desired_size == 1.
  # With a fixed max_unavailable = 1 and only 1 node, EKS terminates the sole
  # node before launching a replacement, leaving the cluster with 0 nodes.
  update_config {
    max_unavailable_percentage = 50
  }

  tags = {
    Name = "${var.cluster_name}-${var.node_group_name}"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_only,
    aws_launch_template.eks_nodes,
  ]
}
