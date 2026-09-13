# Entorno `dev` — laboratorio de formación

Mismos 8 módulos que `envs/prod`, adaptados a una cuenta con **IAM restringido a un catálogo fijo de roles** (no se puede `iam:CreateRole` ni `iam:CreateOpenIDConnectProvider`).

## Qué cambia respecto a `prod`

| | `prod` | `dev` |
|---|---|---|
| Rol de cada Lambda | Uno propio por función (mínimo privilegio) | Uno compartido: `studentLambdaExecutionRole` |
| CI/CD | GitHub Actions vía OIDC (`bootstrap/`) | **Manual, local**, con la sesión SSO del laboratorio |
| Región | `eu-west-1` | `us-east-1` (verificar contra lo que permita el laboratorio) |

## Por qué el despliegue es manual y no vía GitHub Actions

Las credenciales de la sesión SSO (`AWSReservedSSO_StudentLabAccess_...`) son **temporales y caducan en horas**. Automatizar `infra.yml`/`app-deploy.yml` con esas credenciales exigiría refrescar los secrets del repositorio constantemente, y presentarlo como un pipeline "funcionando" sería engañoso — se rompería solo. Para `dev`, el flujo reproducible es local:

```bash
# 1. Autenticarse con el rol del laboratorio (via AWS IAM Identity Center)
aws sso login --profile lab

# 2. Bootstrap (una sola vez; solo crea el backend de tfstate, sin IAM)
cd bootstrap/
terraform init
terraform apply -var="manage_github_oidc=false" \
  -var="github_org=<tu-org>" -var="github_repo=<tu-repo>"

# 3. Entorno dev
cd ../envs/dev
terraform init
terraform apply \
  -var="owner=<tu-nombre>" \
  -var="ses_from_address=<tu-email-verificado>" \
  -var="alarm_email=<tu-email>"
```

## Antes de aplicar: verifica los permisos del rol compartido

El módulo intenta ampliar `studentLambdaExecutionRole` con una policy inline (`aws_iam_role_policy.student_lambda_extra_permissions` en `main.tf`) para cubrir DynamoDB, S3, SES y SQS — `iam:PutRolePolicy` sobre un rol que **ya existe** es una acción distinta de `iam:CreateRole`, y puede estar permitida aunque crear roles nuevos no lo esté.

**Si el `apply` falla en ese recurso concreto**:
1. Pon `attach_extra_permissions_to_shared_role = false`.
2. Revisa a mano en la consola IAM (`Roles → studentLambdaExecutionRole → Permissions`) si el rol ya cubre `dynamodb:*`, `s3:GetObject`/`PutObject`, `ses:SendEmail`, `sqs:SendMessage`.
3. Si no los cubre, las funciones fallarán en tiempo de ejecución con `AccessDeniedException` — no hay forma de arreglarlo desde Terraform sin ese permiso; hay que pedir al administrador del laboratorio que amplíe el rol, o usar únicamente los servicios que ya cubra.

## Empaquetado y despliegue de código (sin CI/CD)

```bash
# Cada Lambda: empaquetar handler + shared/ (solo app/lambdas/*) y subir
cd app/lambdas/list_posts
zip -r ../../../function.zip . ../shared
aws s3 cp ../../../function.zip s3://<lambda_code_bucket>/api/list_posts.zip
aws lambda update-function-code \
  --function-name communly-dev-list-posts \
  --s3-bucket <lambda_code_bucket> --s3-key api/list_posts.zip

# Frontend
cd app/frontend
VITE_API_BASE_URL=<api_gateway_endpoint> \
VITE_COGNITO_DOMAIN=<cognito_hosted_ui_domain> \
VITE_COGNITO_CLIENT_ID=<cognito_user_pool_client_id> \
VITE_REDIRECT_URI=http://localhost:5173/callback \
VITE_LOGOUT_URI=http://localhost:5173 \
npm install && npm run build
aws s3 sync dist/ s3://<frontend_bucket_name> --delete
```

## Lo que NO se garantiza en dev

- **Sin aislamiento de permisos por función** — es el trade-off central de este entorno, documentado en `modules/*/variables.tf` (`shared_execution_role_arn`). Nunca replicar este patrón en `prod`.
- **WAF y la región `us-east-1` no están verificados contra las restricciones reales del laboratorio** — algunos entornos de formación bloquean servicios o regiones adicionales. Si `terraform apply` falla en `module.security`, es razonable quitarlo (`waf_web_acl_arn = null` en `module.storage`) y continuar sin WAF en dev.
