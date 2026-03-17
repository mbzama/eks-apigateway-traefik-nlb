terraform state list

terraform state rm aws_eks_cluster.main
terraform state rm aws_eks_node_group.main

terraform state rm aws_secretsmanager_secret.rds_credentials
terraform state rm aws_secretsmanager_secret_version.rds_credentials

terraform plan

