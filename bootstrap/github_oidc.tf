# Todo este fichero es opcional: si var.manage_github_oidc = false (p.ej.
# una cuenta de laboratorio donde iam:CreateRole/CreateOpenIDConnectProvider
# esta bloqueado), ningun recurso de aqui se crea. El backend de tfstate
# (state_backend.tf) no depende de nada de este fichero.

# Proveedor OIDC de GitHub Actions. Si la cuenta AWS ya tiene este
# proveedor de un proyecto anterior, importar en vez de crear
# (el issuer es global por cuenta, no se puede duplicar).
resource "aws_iam_openid_connect_provider" "github" {
  count = var.manage_github_oidc ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # thumbprint publico del certificado raiz de GitHub
}

data "aws_iam_policy_document" "github_actions_assume" {
  count = var.manage_github_oidc ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restringe el rol exclusivamente a workflows de la rama main de
    # este repositorio concreto. Sin esta condicion, cualquier repo del
    # mismo proveedor OIDC de la cuenta podria asumir el rol.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = var.manage_github_oidc ? 1 : 0

  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume[0].json

  permissions_boundary = aws_iam_policy.ci_boundary[0].arn
}

# Permissions boundary: techo absoluto de lo que este rol puede hacer,
# independientemente de lo permisivo que sea el resto de su policy.
# Limitado a los servicios que este proyecto usa; cualquier otro
# servicio de la cuenta (p.ej. EC2, RDS, Redshift...) queda fuera de
# alcance aunque alguien anada esa accion a la policy por error.
resource "aws_iam_policy" "ci_boundary" {
  count = var.manage_github_oidc ? 1 : 0

  name = "${var.project_name}-ci-boundary"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowedServices"
        Effect = "Allow"
        Action = [
          "dynamodb:*", "lambda:*", "apigateway:*", "cognito-idp:*",
          "s3:*", "cloudfront:*", "wafv2:*", "sns:*", "sqs:*",
          "cloudwatch:*", "logs:*", "iam:*", "ses:*", "sts:GetCallerIdentity",
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy funcional: lo que el rol puede hacer en la practica. Se apoya
# en el tag Project donde el servicio lo soporta; en las acciones de
# creacion (que no pueden condicionarse por un tag que aun no existe)
# se exige que la creacion incluya ese tag (aws:RequestTag), de forma
# que cualquier recurso creado con este rol quede automaticamente
# dentro del alcance auditable por tag.
#
# NOTA: StringEqualsIfExists en aws:RequestTag/Project solo restringe
# las acciones que CREAN o ETIQUETAN recursos (obliga a que todo lo
# nuevo lleve el tag correcto); no puede restringir acciones de
# lectura/borrado sobre recursos que ya existieran sin ese tag. Es una
# limitacion real del modelo de permisos de AWS para roles de CI/CD de
# proposito general -- la permissions boundary de arriba es la defensa
# que de verdad pone un techo, no esta policy por si sola.
data "aws_iam_policy_document" "github_actions_permissions" {
  count = var.manage_github_oidc ? 1 : 0

  statement {
    sid    = "ManageProjectResources"
    effect = "Allow"
    actions = [
      "dynamodb:*", "lambda:*", "apigateway:*", "cognito-idp:*",
      "s3:*", "cloudfront:*", "wafv2:*", "sns:*", "sqs:*",
      "cloudwatch:*", "logs:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
  }

  statement {
    sid    = "ManageOwnIamRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:TagRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:aws:iam::*:role/${var.project_name}-*"]
  }

  statement {
    sid       = "ReadCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
  }

  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.tfstate_locks.arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  count = var.manage_github_oidc ? 1 : 0

  name   = "${var.project_name}-github-actions-policy"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_permissions[0].json
}
