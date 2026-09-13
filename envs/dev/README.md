# Entorno `dev` — laboratorio de formación

Mismos 8 módulos que `envs/prod`, adaptados a una cuenta con **IAM restringido a un catálogo fijo de roles** (no se puede `iam:CreateRole` ni, en la práctica, `iam:PutRolePolicy` sobre roles ya existentes tampoco). Todo lo que distingue a `dev` de `prod` está controlado por variables explícitas — nada se resuelve comentando bloques a mano en `main.tf`.

## Interruptores de este entorno

| Variable | Por defecto | Qué hace |
|---|---|---|
| `student_lambda_role_arn` / `student_lambda_role_name` | resuelve por nombre (`studentLambdaExecutionRole`) | Rol de ejecución compartido por todas las Lambdas, en vez de un rol propio por función |
| `attach_extra_permissions_to_shared_role` | `true` | Intenta ampliar el rol compartido con una policy inline. En la práctica, casi seguro que fallará (`iam:PutRolePolicy` denegado) — ponedlo a `false` en cuanto lo confirméis, no hace falta reintentarlo cada vez |
| `enable_stream_triggers` | `true` | Conecta las Lambdas `fan-out`/`notifications` al Stream de DynamoDB. Requiere `dynamodb:DescribeStream`, `GetRecords`, `GetShardIterator`, `ListStreams` en el rol compartido |
| `mock_ses_notifications` | `true` | La Lambda de notificaciones no llama a SES en absoluto, solo lo registra en el log. El registro de la notificación en DynamoDB se guarda igual, con o sin esto |
| `enable_waf` | `true` | Si el laboratorio no permite `wafv2:*`, ponedlo a `false` — `storage` recibe `waf_web_acl_arn = null` y no se crea el módulo `security` |
| `manage_lambda_code_with_terraform` | `true` | Terraform empaqueta y sube el código de las Lambdas directamente (`archive_file` + `filename`/`source_code_hash`), sin S3 ni pipeline externo — no hace falta ningún paso manual de empaquetado |

## Lo que ya sabemos, tras el primer despliegue real contra este laboratorio concreto

El rol `studentLambdaExecutionRole` de esta cuenta tiene adjuntas `StudentLambdaDynamoDBAccess`, `StudentLambdaS3Access`, `StudentLambdaSNSAccess` y `StudentLambdaSQSAccess`. Comparado con lo que el código necesita:

- ✅ **DynamoDB** (`GetItem`/`PutItem`/`UpdateItem`/`DeleteItem`/`Query`/`BatchWriteItem`) — cubierto.
- ✅ **S3** (`GetObject`/`PutObject`) — cubierto, la subida de imágenes funciona.
- ❌ **`dynamodb:TransactWriteItems`** — falta. **Esto es crítico**: sin él, el trigger `post_confirmation` de Cognito fallaría al confirmar cualquier registro nuevo. Ya está mitigado en el código (`app/cognito-triggers/post-confirmation/index.py` degrada a `needs_username: true` si detecta `AccessDeniedException`, en vez de reventar), pero si en algún momento os conceden este permiso, el registro dejará de necesitar ese paso de "elige tu username" después de confirmar el email.
- ❌ **Acciones de Streams** (`DescribeStream`/`GetRecords`/`GetShardIterator`/`ListStreams`) — falta. Con `enable_stream_triggers=false` esto deja de bloquear el `apply`; el feed personalizado por seguidores queda inactivo hasta que se conceda.
- ❌ **SES** — no hay ninguna política que lo cubra. Con `mock_ses_notifications=true` esto deja de ser un problema: nunca se intenta la llamada real.

Si queréis pedir la ampliación mínima (mucho más fácil de aprobar que una política nueva completa, porque solo añade acciones a algo que ya existe):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DynamoDBTransactionsAndStreams",
      "Effect": "Allow",
      "Action": [
        "dynamodb:TransactWriteItems",
        "dynamodb:DescribeStream",
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator",
        "dynamodb:ListStreams"
      ],
      "Resource": "*"
    }
  ]
}
```

Y, si además interesa que el email de notificaciones funcione de verdad (no es imprescindible, el resto de la app no depende de esto):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SESAccess",
      "Effect": "Allow",
      "Action": ["ses:SendEmail", "ses:SendRawEmail"],
      "Resource": "*"
    }
  ]
}
```

En cuanto os concedan la primera, podéis volver a poner `enable_stream_triggers=true` (y, si además os conceden `TransactWriteItems`, el registro deja de degradar a `needs_username`). Si os conceden la segunda, poned `mock_ses_notifications=false`.

## Por qué el despliegue es manual y no vía GitHub Actions

Las credenciales de la sesión SSO (`AWSReservedSSO_StudentLabAccess_...`) son **temporales y caducan en horas**. Automatizar `infra.yml`/`app-deploy.yml` con esas credenciales exigiría refrescar los secrets del repositorio constantemente, y presentarlo como un pipeline "funcionando" sería engañoso — se rompería solo. Para `dev`, el flujo reproducible es local:

```powershell
# 1. Autenticarse con el rol del laboratorio
aws sso login --profile cursoAWS

# 2. Bootstrap (una sola vez; solo crea el backend de tfstate, sin IAM)
cd bootstrap/
terraform init
terraform apply -var="manage_github_oidc=false" `
  -var="github_org=no-aplica" -var="github_repo=no-aplica"

# 3. Ajustar envs/dev/backend.tf con el bucket real (output del paso anterior)
#    y usar use_lockfile en vez de dynamodb_table (ver nota mas abajo)

# 4. Entorno dev
cd ../envs/dev
terraform init
terraform apply `
  -var="owner=<tu-nombre>" `
  -var="ses_from_address=<tu-email-verificado>" `
  -var="alarm_email=<tu-email>" `
  -var="attach_extra_permissions_to_shared_role=false" `
  -var="enable_stream_triggers=false"
```

**Nota sobre el backend**: si vuestra versión de Terraform muestra el aviso `Deprecated Parameter: dynamodb_table`, usad `use_lockfile = true` en el bloque `backend "s3"` en vez de `dynamodb_table` — es el mecanismo de bloqueo nuevo, nativo de S3, y conviene adoptarlo antes de que exista ningún estado real (cambiarlo después exige migrar el backend).

## Despliegue del código de las Lambdas: gestionado por Terraform, sin pasos manuales

Con `manage_lambda_code_with_terraform = true` (activo por defecto en este entorno), **no hace falta ningún `Compress-Archive`/`aws s3 cp`/`aws lambda update-function-code` manual**. Terraform empaqueta el código de `app/lambdas/*`, `app/stream-consumers/*` y `app/cognito-triggers/*` directamente (usando `archive_file`) y lo sube a cada función vía `filename`/`source_code_hash`, en el mismo `terraform apply` que crea el resto de la infraestructura.

Esto significa que, para desplegar o actualizar el código, basta con volver a aplicar tras cualquier cambio en `app/`:

```powershell
cd envs\dev
terraform apply `
  -var="owner=igarra" `
  -var="ses_from_address=igarra@gmail.com" `
  -var="alarm_email=igarra@gmail.com" `
  -var="attach_extra_permissions_to_shared_role=false" `
  -var="enable_stream_triggers=false"
```

Terraform detecta el cambio de código por el hash del contenido (`output_base64sha256`) y actualiza solo las funciones cuyo código haya cambiado de verdad, sin tocar las demás.

**Cómo verificarlo tras un `apply`:**
```powershell
aws lambda get-function --function-name communly-dev-list-posts --query "Configuration.CodeSha256"
```
Si coincide con lo que Terraform acaba de subir, el despliegue fue correcto.

**Nota**: cada módulo (`api-lambdas`, `stream-consumers`, `cognito`) genera los `.zip` localmente junto a sus propios ficheros (`dist-*.zip`, ya en `.gitignore`) — no se suben a S3 ni al repositorio, son artefactos de build efímeros.

Si en algún momento preferís desactivar esto (por ejemplo, para probar el flujo de despliegue manual que sí usa `prod`), poned `manage_lambda_code_with_terraform=false` y seguid el patrón manual de siempre:

```powershell
$build = Join-Path $env:TEMP "list_posts_build"
New-Item -ItemType Directory -Force -Path $build | Out-Null
Copy-Item app\lambdas\list_posts\index.py $build
Copy-Item app\lambdas\shared $build -Recurse
Compress-Archive -Path "$build\*" -DestinationPath "$env:TEMP\list_posts.zip" -Force

aws s3 cp "$env:TEMP\list_posts.zip" s3://communly-dev-lambda-code/api/list_posts.zip
aws lambda update-function-code --function-name communly-dev-list-posts `
  --s3-bucket communly-dev-lambda-code --s3-key api/list_posts.zip
```

## Frontend, en local

```powershell
cd app\frontend
npm install

cd ..\..\envs\dev
terraform output api_gateway_endpoint
terraform output cognito_hosted_ui_domain
terraform output cognito_user_pool_client_id
cd ..\..\app\frontend

$env:VITE_API_BASE_URL = "<api_gateway_endpoint>"
$env:VITE_COGNITO_DOMAIN = "https://<cognito_hosted_ui_domain>"
$env:VITE_COGNITO_CLIENT_ID = "<cognito_user_pool_client_id>"
$env:VITE_REDIRECT_URI = "http://localhost:5173/callback"
$env:VITE_LOGOUT_URI = "http://localhost:5173"

npm run dev
```

## Lo que NO se garantiza en dev

- **Sin aislamiento de permisos por función** — trade-off central de este entorno, nunca replicar en `prod`.
- **Sin feed personalizado por seguidores** mientras `enable_stream_triggers=false` — el resto de la app (posts, comentarios, likes, perfiles) no depende de esto.
- **Sin email real de notificaciones** mientras `mock_ses_notifications=true` — la notificación se guarda igual en `/me/notifications`, solo no llega el correo.
- **Cambiar de `username` tras el registro puede fallar** si falta `dynamodb:TransactWriteItems` — a diferencia del registro inicial (ya mitigado), esta ruta (`update_profile`) todavía no degrada con la misma gracia; es una mejora pendiente si el permiso no llega a concederse.
