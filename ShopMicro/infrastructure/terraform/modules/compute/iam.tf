resource "aws_iam_role" "k8s_node_role" {
  name = "${var.env_prefix}-k8s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "k8s_node_ecr" {
  role       = aws_iam_role.k8s_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "k8s_node_profile" {
  name = "${var.env_prefix}-k8s-node-profile"
  role = aws_iam_role.k8s_node_role.name
}
