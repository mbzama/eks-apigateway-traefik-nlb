# ─────────────────────────────────────────────────────────────────────────────
# Security Group – EKS Control Plane
# Allows the API server to reach worker nodes and vice-versa.
# EKS manages most of the intra-cluster rules automatically; we expose
# port 443 so that kubectl (and the Terraform Kubernetes/Helm providers)
# can reach the public endpoint.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS control plane security group"
  vpc_id      = aws_vpc.main.id

  # Allow all outbound (needed for API server to pull images, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

# Nodes can communicate with each other on any port within the VPC
resource "aws_security_group_rule" "eks_cluster_ingress_nodes" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
  description              = "Allow worker nodes to reach the API server"
}

# ─────────────────────────────────────────────────────────────────────────────
# Security Group – EKS Worker Nodes
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "eks_nodes" {
  name        = "${var.cluster_name}-nodes-sg"
  description = "EKS worker node security group"
  vpc_id      = aws_vpc.main.id

  # Allow all outbound (nodes need internet access via NAT to pull images)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name                                        = "${var.cluster_name}-nodes-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Nodes can communicate with each other (required for pod-to-pod traffic)
resource "aws_security_group_rule" "eks_nodes_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow node-to-node communication"
}

# Nodes accept traffic from the control plane
resource "aws_security_group_rule" "eks_nodes_ingress_cluster" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Allow control plane to reach worker nodes"
}

# ─────────────────────────────────────────────────────────────────────────────
# Security Group – API Gateway VPC Link
#
# Flow: API Gateway → VPC Link → Traefik NLB (port 80)
# The VPC Link SG only needs outbound access to the NLB on port 80.
# NLBs themselves do not have security groups; traffic is controlled by
# the node-level SG rules (the K8s cloud controller opens the NLB port
# on the node SG automatically when a LoadBalancer Service is created).
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "vpc_link" {
  name        = "${var.cluster_name}-vpc-link-sg"
  description = "Security group for API Gateway VPC Link - egress to Traefik NLB on port 80"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow outbound HTTP to the internal Traefik NLB"
  }

  tags = {
    Name = "${var.cluster_name}-vpc-link-sg"
  }
}
