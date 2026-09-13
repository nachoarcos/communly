# Communly

Plataforma de comunidad y publicación de contenidos estilo dev.to/Reddit: los usuarios se registran, publican artículos en markdown y comentan publicaciones de otros. El reto de producto es **mucha lectura, poca escritura** — la mayoría de visitantes leen sin estar registrados.

- **Repositorio Git público** con historial de commits coherente.
- **Infraestructura**: 100% Terraform, salvo el bootstrap mínimo (ver [`bootstrap/`](#paso-0--bootstrap-manual-una-sola-vez)).
- **Plataforma**: AWS, arquitectura serverless (ver [Decisión arquitectónica](#decisión-arquitectónica)).

---

## Índice

1. [Descripción funcional](#descripción-funcional)
2. [Diagrama de arquitectura](#diagrama-de-arquitectura)
3. [Decisión arquitectónica](#decisión-arquitectónica)
4. [Modelo de datos](#modelo-de-datos)
5. [Estructura del repositorio](#estructura-del-repositorio)
6. [Instrucciones de despliegue](#instrucciones-de-despliegue)
7. [Estimación de coste mensual](#estimación-de-coste-mensual)
8. [Seguridad](#seguridad)
9. [Observabilidad](#observabilidad)
10. [FinOps](#finops)
11. [Instrucciones de destrucción](#instrucciones-de-destrucción)
12. [Limitaciones conocidas y trabajo pendiente](#limitaciones-conocidas-y-trabajo-pendiente)

---

## Descripción funcional

### MVP

**Usuarios anónimos**
- Listado paginado de posts publicados, ordenados por fecha (`GET /posts`).
- Lectura de un post con sus comentarios (`GET /posts/{postId}`, `GET /posts/{postId}/comments`).

**Usuarios registrados**
- Registro y login con email + contraseña, vía Cognito Hosted UI.
- Crear, editar y borrar (lógicamente) posts en markdown, como borrador o publicados.
- Comentar posts.

### Extensiones implementadas

| Extensión | Estado | Dónde |
|---|---|---|
| Subida de imágenes (S3 + CDN) | ✅ Completa | `request_image_upload` + `modules/storage` |
| Tags / categorías y filtrado | ✅ Completa | `list_posts_by_tag`, ítems `TAG#` |
| Likes en posts | ✅ Completa | `toggle_like` |
| Seguir usuarios + feed personalizado | ✅ Completa | `toggle_follow`, `list_user_feed`, fan-out por Streams |
| Notificación por email al comentar | ✅ Completa | Stream consumer `notifications` + SES |
| Perfil de usuario con avatar y bio | ✅ Completa | `get_user_profile`, `get_own_profile`, `update_profile` |
| Panel admin: cola de denuncias | ⚠️ Parcial | `list_moderation_queue`, `resolve_report` marcan y resuelven denuncias, pero **no borran el post ni banean al usuario automáticamente** — la acción de moderación de fondo queda como trabajo manual/pendiente (ver [Limitaciones](#limitaciones-conocidas-y-trabajo-pendiente)) |

### Frontend

SPA en React + Vite (`app/frontend`), sin librería de estado ni UI pesada — solo `react-router-dom`, `marked` y `dompurify`. Login por Authorization Code + PKCE contra el Hosted UI de Cognito, sin SDK de OAuth externo.

---

## Diagrama de arquitectura

[`communly_arquitectura.drawio`](./communly_arquitectura.drawio) — abrir en [app.diagrams.net](https://app.diagrams.net) o la extensión de VS Code.

Resumen del flujo:

```
Usuario ──> CloudFront (+ WAF) ──┬──> S3 (frontend estatico)          /*
                                  ├──> API Gateway (HTTP API)          /api/*
                                  │      │  JWT Authorizer (Cognito)
                                  │      └──> 20 Lambdas (Python 3.12)
                                  │             │
                                  │             ├──> DynamoDB (single-table + Streams)
                                  │             │       │
                                  │             │       ├──> Lambda fan-out ──> DynamoDB (FEED#)
                                  │             │       └──> Lambda notifications ──> SES
                                  │             │
                                  │             └──> S3 (imagenes, URL prefirmada)
                                  │
                                  └──> S3 (imagenes de posts)          /images/*

Cognito User Pool ──> Lambda triggers (pre-signup / post-confirmation) ──> DynamoDB

CloudWatch Logs/Alarms <── todo lo anterior ──> SNS ──> email del equipo
GitHub Actions ──> S3 (código Lambda / build frontend) ──> Lambda update-function-code / CloudFront invalidation
```

---

## Decisión arquitectónica

Esta sección documenta el proceso real de decisión, incluyendo el camino descartado — es intencional dejarlo así, porque el enunciado pide explícitamente "qué alternativas valoraste y por qué descartaste el resto", y la alternativa descartada aquí se evaluó en profundidad, no de pasada.

### Alternativa considerada y descartada: EC2/ECS Fargate + RDS PostgreSQL + ALB

Se diseñó primero una arquitectura clásica en contenedores: ECS Fargate + RDS PostgreSQL Multi-AZ + ALB + NAT Gateway ×2, con S3/CloudFront para el frontend. Se descartó por dos motivos, uno de coste y uno de encaje:

1. **Coste en reposo.** Esta arquitectura tiene un **suelo fijo de ~180$/mes que se paga exista tráfico o no** (el NAT Gateway por sí solo son ~67$/mes). Un proyecto de portfolio tiene un patrón de tráfico de ráfagas impredecibles sobre una base casi nula — pagar capacidad reservada para eso es la decisión que hay que justificar, no al revés.
2. Se evaluó explícitamente el patrón de modelado social documentado por AWS para DynamoDB (single-table, fan-out de timeline) como alternativa a RDS, y se concluyó en su momento que el patrón estaba optimizado para timelines por grafo de follows, no para el listado global cronológico que es el núcleo del MVP. Ese análisis llevó a la arquitectura de contenedores. **Se revisó después** (ver siguiente punto) porque cambió la pregunta relevante: no "¿qué modela mejor un timeline?", sino "¿qué arquitectura tiene menor coste en reposo para el patrón de tráfico real de este proyecto?".

### Arquitectura elegida: Lambda + DynamoDB + API Gateway + Cognito (serverless)

- **Coste en reposo prácticamente nulo.** Lambda, DynamoDB on-demand y API Gateway no cobran nada sin tráfico. El único coste fijo que queda es el WAF (~10$/mes) — ver [estimación de coste](#estimación-de-coste-mensual).
- **HA y backups nativos, sin configuración de red.** DynamoDB replica automáticamente entre 3 AZs y soporta point-in-time recovery con un flag; no hay VPC, subnets ni NAT que diseñar.
- **Aislamiento de permisos por función.** Cada una de las 20 Lambdas tiene su propio rol IAM acotado por prefijo de partición (`dynamodb:LeadingKeys`) — el radio de explosión de cualquier endpoint comprometido está limitado a lo que esa función necesita, a diferencia de un único rol de tarea compartido por todo un backend en contenedores.
- **El feed global (el access pattern núcleo del MVP)** se resuelve con un índice **sharded y sparse** (`GSI1PK=POSTS#<shard>`, solo existe si `status=published`) — la mitigación estándar documentada para el anti-patrón de partición única en DynamoDB, con `N=5` shards, muy por encima de cualquier pico razonable de publicación a esta escala.
- **Cognito** sustituye la autenticación propia: gestiona hashing de contraseñas, verificación de email y emisión de JWT, con el **JWT Authorizer nativo de API Gateway** validando cada petición sin código propio de verificación.

Trade-offs aceptados explícitamente, no ocultados:
- **Curva de aprendizaje del diseño single-table** — mitigada documentando cada access pattern antes de escribir código (ver [Modelo de datos](#modelo-de-datos)).
- **Consistencia eventual** en el feed personalizado (fan-out) y en el contador de likes — aceptable porque el dominio lo permite.
- **`dynamodb:LeadingKeys` no está soportado en `TransactWriteItems`** — la función `update_profile` (cambio de username) necesita permiso sobre toda la tabla para esa acción concreta; se compensa siendo una función aislada y muy estrecha en lo que hace, no comparte permisos con otras.
- **El JWT Authorizer nativo de API Gateway no evalúa `cognito:groups`** — las rutas `admin_only` (`list_moderation_queue`, `resolve_report`) comprueban el grupo `admins` dentro del propio handler, leyendo el claim del token ya validado.

### Otras alternativas descartadas más brevemente

- **API Gateway como capa adicional delante de un backend en contenedores**: descartada en la arquitectura clásica porque el ALB + WAF ya cubrían TLS, autenticación y rate-limiting sin coste adicional. Al pivotar a serverless, API Gateway pasa a ser la pieza natural (integración directa con Lambda vía proxy, sin VPC Link ni NLB de por medio).
- **Aurora Serverless v2 en vez de DynamoDB**: se mencionó como híbrido posible (modelo relacional con escalado a near-zero), descartada por la complejidad de pooling de conexiones desde Lambda (RDS Proxy) frente al beneficio marginal de coste a esta escala.

---

## Modelo de datos

Tabla única `communly-<environment>` en DynamoDB, con 2 GSIs. Ver [`modules/dynamodb/dynamodb.tf`](./modules/dynamodb/dynamodb.tf) para la definición completa y comentada de cada índice.

| Necesidad | Clave |
|---|---|
| Perfil por sub / por username | `PK=USER#<sub>` o `PK=USERNAME#<username>`, `SK=PROFILE` |
| Post | `PK=POST#<id>`, `SK=META` |
| Feed global (sharded, sparse) | `GSI1PK=POSTS#<shard 0..4>`, `GSI1SK=PUBLISHED#<publishedAt>#<id>` — solo existe si `status=published` |
| Comentarios de un post | `PK=POST#<id>`, `SK=COMMENT#<ts>#<id>` |
| Posts / comentarios / likes de un usuario | `GSI2PK=USER#<sub>`, `GSI2SK=<TIPO>#<ts>#<id>` |
| Posts por tag | `GSI2PK=TAG#<tag>` |
| A quién sigue / seguidores | mismo ítem, tabla base (`FOLLOWING#`) + proyección en GSI1 (`FOLLOWER#`) |
| Feed personalizado (fan-out) | `PK=USER#<sub>`, `SK=FEED#<ts>#<id>`, con TTL |
| Notificaciones | `PK=USER#<sub>`, `SK=NOTIFICATION#<ts>#<id>` |
| Cola de moderación (sparse) | `GSI2PK=MODERATION#OPEN` — se elimina el atributo al resolver |

`DynamoDB Streams` (`NEW_AND_OLD_IMAGES`) alimenta dos Lambdas asíncronas: **fan-out** del feed y **notificaciones** por email, cada una con su propia DLQ (SQS) y política de reintentos acotada.

---

## Estructura del repositorio

```
.
├── bootstrap/              # Terraform manual, una sola vez (tfstate backend + rol OIDC)
├── envs/prod/              # Entorno Terraform que instancia todos los módulos
├── modules/
│   ├── dynamodb/
│   ├── api-lambdas/        # 20 funciones, una por access pattern (generadas por for_each)
│   ├── stream-consumers/   # fan-out + notifications, con DLQ y reintentos
│   ├── cognito/            # User Pool, App Client, triggers pre-signup/post-confirmation
│   ├── api-gateway/        # HTTP API + JWT Authorizer
│   ├── storage/            # S3 (frontend/imágenes/código) + CloudFront
│   ├── security/           # WAF (Web ACL, us-east-1)
│   └── observability/      # Log groups, alarmas, SNS
├── app/
│   ├── lambdas/            # Código Python de las Lambdas de API
│   ├── stream-consumers/   # fan-out, notifications
│   ├── cognito-triggers/   # pre-signup, post-confirmation
│   └── frontend/           # SPA React + Vite
└── .github/workflows/
    ├── infra.yml           # terraform plan/apply (push a main sobre modules/** o envs/**)
    └── app-deploy.yml       # build + deploy de las Lambdas y del frontend (push sobre app/**)
```

---

## Instrucciones de despliegue

### Requisitos previos

- Cuenta AWS con permisos de administrador (solo para el paso de `bootstrap/`).
- Terraform ≥ 1.7, AWS CLI configurado localmente para el bootstrap.
- Un repositorio de GitHub con Actions habilitado.
- Una dirección de email verificable en SES (modo sandbox por defecto).

### Paso 0 — Bootstrap (manual, una sola vez)

```bash
cd bootstrap/
terraform init
terraform apply \
  -var="github_org=<tu-org-o-usuario>" \
  -var="github_repo=<nombre-del-repo>"
```

Esto crea el bucket de `tfstate`, la tabla de locks, el proveedor OIDC de GitHub y el rol `communly-github-actions` con permissions boundary. Guarda los outputs — los necesitas en el paso siguiente. El estado de este `apply` es **local** (no se sube al repo, ver `.gitignore`); cópialo a un sitio seguro.

### Paso 1 — Variables del repositorio de GitHub

En *Settings → Secrets and variables → Actions → Variables*, crea:

| Variable | Valor |
|---|---|
| `AWS_GITHUB_ACTIONS_ROLE_ARN` | output `github_actions_role_arn` del bootstrap |
| `AWS_REGION` | `eu-west-1` |
| `PROJECT_NAME` | `communly` |
| `ENVIRONMENT` | `prod` |
| `PROJECT_OWNER` | tu nombre |
| `SES_FROM_ADDRESS` | email verificado en SES |
| `ALARM_EMAIL` | email que recibe alarmas |

### Paso 2 — Primer despliegue de infraestructura (fase 1)

Push a `main` que toque `envs/**` o `modules/**` dispara `infra.yml`. Con los valores por defecto (`communly.example.com`, `localhost:5173`) para `callback_urls`/`cors_allowed_origins`, el primer `apply` crea los 8 módulos completos.

> **Por qué hace falta una fase 2**: `callback_urls` de Cognito no puede depender del dominio de CloudFront sin cerrar un ciclo real en el grafo de Terraform (ver comentario en `envs/prod/main.tf`, junto a `module.cognito`). Es un ciclo genuino, no una limitación de este proyecto.

### Paso 3 — Variables de fase 2

Tras el primer `apply`, ejecuta:

```bash
cd envs/prod && terraform output
```

Y con `cloudfront_domain_name`, `api_gateway_endpoint`, `cognito_user_pool_id`, `cognito_user_pool_client_id`, `cognito_hosted_ui_domain`, `frontend_bucket_name`, `images_bucket_name`, `alarms_topic_arn`:

1. Actualiza `var.callback_urls`, `var.logout_urls` y `var.cors_allowed_origins` en `envs/prod/variables.tf` (o vía `-var`) con el dominio real de CloudFront, y vuelve a aplicar — solo actualiza el cliente de Cognito y el CORS de API Gateway, no recrea nada.
2. Añade las variables de GitHub que faltan: `LAMBDA_CODE_BUCKET`, `FRONTEND_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`, `API_BASE_URL` (`https://<dominio-cloudfront>/api`), `COGNITO_HOSTED_UI_DOMAIN`, `COGNITO_CLIENT_ID`, `FRONTEND_REDIRECT_URI`, `FRONTEND_LOGOUT_URI`.

### Paso 4 — Primer despliegue de aplicación

Push a `main` que toque `app/**` dispara `app-deploy.yml`: empaqueta y publica las 20 funciones Lambda (sustituyendo los placeholders de Terraform) y construye/sincroniza el frontend con las variables `VITE_*` inyectadas en build time.

### Paso 5 — Pasos manuales restantes

- **Confirmar la suscripción de SNS**: llega un email a `ALARM_EMAIL`, hay que aceptarlo a mano.
- **SES en modo sandbox**: hasta pedir salir del sandbox, solo se puede enviar a direcciones verificadas individualmente — verificar la dirección de prueba en la consola de SES.
- **Promover un usuario a admin**: `aws cognito-idp admin-add-user-to-group --user-pool-id <id> --username <email> --group-name admins` (ver `modules/cognito/groups.tf`).

---

## Estimación de coste mensual

Suelo (cero tráfico) vs tráfico bajo-moderado esperado para un proyecto de portfolio. Tarifas 2026, us-east-1; eu-west-1 puede ser 10-20% mayor.

| Servicio | En reposo | Con tráfico bajo-moderado |
|---|---|---|
| Lambda (20 funciones) | $0 | $0 (dentro de la capa gratuita permanente: 1M invocaciones + 400.000 GB-s/mes) |
| DynamoDB on-demand | ~$0,45 (storage + PITR) | ~$0,70 |
| API Gateway (HTTP API) | $0 | ~$0,07 |
| Cognito | $0 | $0 (Essentials, hasta 10.000 MAU) |
| CloudFront | ~$1 | ~$10 |
| AWS WAF | ~$10 (fijo, Web ACL + reglas) | ~$10 |
| S3 (frontend + imágenes + código) | ~$1 | ~$3 |
| CloudWatch Logs & Alarms | ~$1 | ~$5 |
| SES | $0 | ~$1 |
| SNS / SQS | $0 | ~$1 |
| AWS Budgets | $0 | $0 |
| **TOTAL** | **≈ $12-13/mes** | **≈ $30-31/mes** |

Comparado con la arquitectura descartada (ECS Fargate + RDS + ALB + NAT): **~183$/mes con tráfico bajo, ~150$/mes de suelo fijo en reposo** — esta arquitectura reduce el coste en más del 80%, y el motivo de fondo (pago por uso vs capacidad reservada, para un patrón de tráfico en ráfagas) es el argumento central de la [decisión arquitectónica](#decisión-arquitectónica).

La partida que domina el coste ya no es un componente de red que está "encendido" sin razón (como el NAT Gateway antes) — son **CloudFront y WAF**, dos costes justificados por producto y seguridad.

---

## Seguridad

- **IAM de mínimo privilegio por función**: cada una de las Lambdas tiene su propio rol, acotado por `dynamodb:LeadingKeys` al prefijo de partición que necesita (excepción documentada: `update_profile`, que usa `TransactWriteItems`, no soportado por esa condición).
- **Autenticación**: Cognito User Pool, JWT Authorizer nativo en API Gateway, PKCE en el frontend (sin secreto de cliente, apropiado para una SPA).
- **Secretos fuera del código**: no hay contraseñas de base de datos que gestionar (Cognito es la fuente de verdad de credenciales); las variables de Lambda no contienen secretos.
- **HTTPS**: forzado en CloudFront (`viewer_protocol_policy`) y en API Gateway (HTTPS por defecto).
- **WAF**: managed rule groups (`CommonRuleSet`, `KnownBadInputsRuleSet`) + rate-based rule por IP.
- **CI/CD sin credenciales de larga duración**: OIDC entre GitHub Actions y AWS, con permissions boundary como techo del rol de despliegue.
- **Buckets S3 privados**: acceso exclusivo vía CloudFront con Origin Access Control, sin políticas públicas.

## Observabilidad

- **Logs centralizados**: un log group por función Lambda (`modules/observability/log_groups.tf`) + access logs de API Gateway.
- **Alarmas activas**: errores por función Lambda, 5xx en API Gateway, throttling en DynamoDB, mensajes en las DLQ de `stream-consumers` — todas notifican al mismo topic SNS.

## FinOps

- **Etiquetado**: `Project`/`Environment`/`Owner` vía `default_tags` del provider en `envs/prod/providers.tf`, aplicado automáticamente a todo recurso que soporte tags.
- **AWS Budgets**: pendiente de instanciar como módulo — hoy documentado en la estimación de coste, no configurado como alarma de presupuesto activa (ver [Limitaciones](#limitaciones-conocidas-y-trabajo-pendiente)).

---

## Instrucciones de destrucción

```bash
cd envs/prod
terraform destroy
```

Antes de destruir en un entorno real (no aplica si `environment != "prod"`):
1. **DynamoDB tiene `deletion_protection_enabled = true` en prod** — hay que desactivarlo primero (cambiar el flag y `terraform apply`, o `aws dynamodb update-table --deletion-protection-enabled false`).
2. **Cognito tiene `deletion_protection = "ACTIVE"` en prod** — mismo procedimiento, vía `aws cognito-idp update-user-pool`.
3. **Los buckets S3 no vacíos bloquean el `destroy`** — o se vacían a mano (`aws s3 rm s3://<bucket> --recursive`), o se añade `force_destroy = true` temporalmente antes de destruir.

El `bootstrap/` (backend de tfstate + rol OIDC) se destruye aparte y al final, manualmente, solo si se quiere eliminar el proyecto por completo:

```bash
cd bootstrap/
terraform destroy
```

---

## Limitaciones conocidas y trabajo pendiente

Documentadas aquí en vez de ocultarlas:

- **Moderación incompleta**: `resolve_report` marca la denuncia como resuelta pero no borra el post ni banea al usuario — falta la acción de fondo (llamaría a la misma lógica de `delete_post`, sin la comprobación de autoría, más una marca de "banned" en el perfil).
- **`toggle_like` no comprueba el estado previo**: el botón de "me gusta" del frontend siempre arranca en `false`, aunque el usuario ya hubiera dado like antes de cargar la página.
- **AWS Budgets no está en Terraform**: la estimación de coste está documentada, pero la alarma de presupuesto real no se ha instanciado como recurso.
- **`update_profile` con `TransactWriteItems` sin acotar por prefijo**: limitación real de IAM, no un descuido — documentada en la sección de seguridad.
- **Sin dominio propio**: se usa el dominio por defecto de CloudFront (`*.cloudfront.net`); añadir uno propio requiere un certificado ACM en `us-east-1` y un alias, no incluido.
- **Consistencia eventual** en el feed personalizado (fan-out asíncrono vía Streams) y en el contador de likes — aceptado por diseño, ver [decisión arquitectónica](#decisión-arquitectónica).
