data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^arn:aws:iam::[0-9]+:oidc-provider\\//", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }
    
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^arn:aws:iam::[0-9]+:oidc-provider\\//", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  
  tags = {
    "ServiceAccountName"      = var.service_account
    "ServiceAccountNamespace" = var.namespace
  }
}

resource "aws_iam_policy" "this" {
  count = var.policy_json != null ? 1 : 0
  
  name        = var.role_name
  description = "Policy for ${var.role_name}"
  policy      = var.policy_json
}

resource "aws_iam_role_policy_attachment" "custom_policy" {
  count = var.policy_json != null ? 1 : 0
  
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this[0].arn
}

resource "aws_iam_role_policy_attachment" "additional_policies" {
  for_each = var.policy_arns != null ? toset(var.policy_arns) : []
  
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}