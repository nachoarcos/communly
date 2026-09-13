# Communly

Communly es una plataforma de comunidad y publicación de contenidos, en la línea de dev.to o Reddit: la gente se registra, escribe artículos en markdown y comenta lo que escriben los demás. El problema de producto que de verdad condiciona todo el diseño no es "cómo guardo un post", es este: **la inmensa mayoría del tráfico va a ser gente leyendo sin haberse registrado nunca**. Eso es lo primero que hay que resolver bien, y es el hilo conductor de casi todas las decisiones que se explican en este documento.

- **Repositorio Git público**, con un historial de commits que intenta reflejar cómo se fue tomando cada decisión, no solo el resultado final.
- **Infraestructura**: prácticamente el 100% en Terraform. La única excepción deliberada es el bootstrap inicial (ver [`bootstrap/`](#paso-0--bootstrap-manual-una-sola-vez)), y hay una razón técnica concreta para que así sea, no es dejadez.
- **Plataforma**: AWS, con una arquitectura serverless que no fue la primera que probamos (ver [Decisión arquitectónica](#decisión-arquitectónica)).

---

## Índice

1. [Descripción funcional](#descripción-funcional)
2. [Diagrama de arquitectura](#diagrama-de-arquitectura)
3. [Decisión arquitectónica](#decisión-arquitectónica)
4. [Modelo de datos](#modelo-de-datos)
5. [Red y superficie de exposición](#red-y-superficie-de-exposición)
6. [Escalabilidad](#escalabilidad)
7. [Entorno de laboratorio (`dev`) frente a producción](#entorno-de-laboratorio-dev-frente-a-producción)
8. [Estructura del repositorio](#estructura-del-repositorio)
9. [Instrucciones de despliegue](#instrucciones-de-despliegue)
10. [Estimación de coste mensual](#estimación-de-coste-mensual)
11. [Seguridad](#seguridad)
12. [Observabilidad](#observabilidad)
13. [FinOps](#finops)
14. [Instrucciones de destrucción](#instrucciones-de-destrucción)
15. [Limitaciones conocidas](#limitaciones-conocidas)
16. [Mejoras futuras](#mejoras-futuras)

---

## Descripción funcional

### MVP

**Usuarios anónimos**
- Listado paginado de posts publicados, ordenado por fecha (`GET /posts`).
- Lectura de un post con sus comentarios (`GET /posts/{postId}`, `GET /posts/{postId}/comments`).

**Usuarios registrados**
- Registro y login con email y contraseña, a través del Hosted UI de Cognito — no hay una pantalla de login propia, y eso es intencional (se explica más abajo por qué).
- Crear, editar y borrar posts en markdown, como borrador o ya publicados.
- Comentar en cualquier post.

### Extensiones implementadas

No nos quedamos en el MVP mínimo. Estas son las extensiones que sí llegaron a producción, con su estado real:

| Extensión | Estado | Dónde |
|---|---|---|
| Subida de imágenes (S3 + CDN) | ✅ Completa | `request_image_upload` (`POST /me/images`, sin depender de un post ya creado) + botón de subida en `NewPost`/`EditPost`/comentarios |
| Tags / categorías y filtrado | ✅ Completa | `list_posts_by_tag`, ítems `TAG#` |
| Likes en posts | ✅ Completa | `toggle_like` |
| Seguir usuarios + feed personalizado | ✅ Completa | `toggle_follow`, `list_user_feed`, fan-out por Streams |
| Notificación por email al comentar | ✅ Completa | Stream consumer `notifications` + SES |
| Perfil de usuario con avatar y bio | ✅ Completa | `get_user_profile`, `get_own_profile`, `update_profile` |
| Panel de administración: cola de denuncias | ⚠️ Parcial | `list_moderation_queue` y `resolve_report` existen y funcionan, pero la resolución de una denuncia hoy solo la marca como cerrada — **no borra el post ni banea al usuario automáticamente**. Ver [Mejoras futuras](#mejoras-futuras) |

Preferimos dejar esa última fila en amarillo antes que maquillarla. Es perfectamente defendible en un proyecto de este alcance, y es mejor que se note que lo hemos decidido nosotros a que se descubra en una demo.

### Frontend

Una SPA en React + Vite (`app/frontend`), deliberadamente ligera: sin gestor de estado externo, sin librería de componentes, solo lo justo — `react-router-dom` para las rutas, `marked` para renderizar el markdown y `dompurify` para no fiarnos ciegamente de ese HTML generado. El login se resuelve con Authorization Code + PKCE contra el Hosted UI de Cognito, sin ningún SDK de OAuth de por medio; son unas 150 líneas de código que hacen exactamente lo que tienen que hacer y nada más.

---

## Diagrama de arquitectura

El diagrama completo está en [`communly_arquitectura.drawio`](./communly_arquitectura.drawio) — se abre en [app.diagrams.net](https://app.diagrams.net) o con la extensión de draw.io de VS Code. Aquí va un resumen en texto para quien solo quiera hacerse una idea rápida antes de abrirlo:

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

Lo que salta a la vista si has visto antes diagramas de arquitecturas "clásicas" es lo que **no** hay: ni una VPC, ni una subred, ni un NAT Gateway, ni un balanceador de carga. No es que se nos olvidara dibujarlos — es que no existen, y eso es justamente la decisión que se explica a continuación.

---

## Decisión arquitectónica

Vamos a ser transparentes con algo: esta no fue la primera arquitectura que diseñamos. Empezamos por otro camino, lo llevamos bastante lejos, y lo acabamos descartando. Nos parece más honesto contar ese recorrido completo que presentar la decisión final como si hubiera sido obvia desde el principio — porque no lo fue, y el proceso de descartar la primera opción es en sí mismo parte de la justificación de la segunda.

### Primer intento: EC2/ECS Fargate + RDS PostgreSQL + ALB

La primera versión del diseño era la arquitectura "de manual" para una aplicación web con estado: contenedores en ECS Fargate corriendo la API, una base de datos relacional en RDS PostgreSQL con Multi-AZ para alta disponibilidad, un Application Load Balancer delante, y NAT Gateways para que los contenedores en subredes privadas pudieran salir a internet. S3 y CloudFront para servir el frontend. Sobre el papel, es una arquitectura sólida, bien entendida por cualquier equipo de infraestructura, y no hay nada "malo" en ella en abstracto.

El problema apareció al hacer números y al pensar de verdad en el patrón de tráfico real del proyecto:

**El coste no depende del uso, depende de que el reloj avance.** Calculamos que esta arquitectura tiene un suelo fijo de en torno a 180 $ al mes que se paga exista una sola visita o ninguna — y de eso, los NAT Gateway por sí solos suponen unos 67 $/mes, simplemente por estar encendidos. Un proyecto de portfolio no tiene un tráfico constante: tiene rachas completamente impredecibles (el día que lo enseñas en una entrevista, el día que lo compartes en LinkedIn) sobre una base que la mayor parte del tiempo es prácticamente cero. Pagar capacidad reservada, mes tras mes, para un perfil de tráfico que es rachas de actividad sobre silencio, es la decisión que hay que justificar — no lo contrario.

**También evaluamos, y descartamos, ir a DynamoDB dentro de ese mismo esquema de contenedores.** Existe un patrón de modelado bastante conocido que AWS documenta para aplicaciones tipo red social (single-table design con fan-out de timeline), y llegamos a analizarlo en profundidad. La conclusión en ese momento fue que ese patrón está pensado y optimizado para resolver *timelines por grafo de seguidores* — no encaja igual de bien con el listado global y cronológico que es el núcleo real del MVP (un feed público, no un timeline personalizado). Ese análisis nos hizo quedarnos, en ese momento, con el modelo relacional en RDS.

Lo interesante es que **esa conclusión era correcta para la pregunta que nos estábamos haciendo, pero la pregunta estaba mal planteada.** Nos estábamos preguntando "¿qué tecnología modela mejor un timeline?", cuando la pregunta que de verdad importaba para este proyecto era otra: "¿qué arquitectura tiene menor coste cuando no hay tráfico, dado que el tráfico de este proyecto en concreto va a ser así?". En cuanto reformulamos la pregunta, la respuesta cambió.

### La arquitectura que finalmente construimos: serverless de punta a punta

Lambda + DynamoDB + API Gateway + Cognito, sin ningún componente que cobre por estar encendido:

- **El coste en reposo es, a efectos prácticos, cero.** Lambda no cobra sin invocaciones, DynamoDB en modo on-demand no cobra sin lecturas ni escrituras, API Gateway no cobra sin peticiones. El único gasto que sigue existiendo pase lo que pase es el WAF, unos 10 $/mes — y lo asumimos con gusto porque es un coste de seguridad, no de "tener algo encendido sin usarlo". Los números completos están en la [estimación de coste](#estimación-de-coste-mensual).

- **La alta disponibilidad viene de fábrica, sin que nosotros diseñemos ni una subred.** DynamoDB replica los datos entre varias zonas de disponibilidad de forma automática, y activar recuperación a un punto en el tiempo es literalmente un booleano en Terraform. Con la arquitectura anterior, conseguir lo mismo exigía diseñar subredes públicas y privadas en dos AZs, Multi-AZ en RDS, y NAT Gateway redundante — aquí, esa complejidad entera desaparece porque el propio servicio ya la resuelve.

- **Cada función Lambda tiene su propio rol de IAM**, acotado por prefijo de partición de DynamoDB (`dynamodb:LeadingKeys`). Esto no es un detalle cosmético: significa que si alguien encuentra una vulnerabilidad de inyección en, por ejemplo, el endpoint de crear comentarios, lo que consigue explotar son exactamente los permisos de *esa* función — no los de toda la aplicación. En un backend monolítico en contenedores, lo habitual es un único rol de tarea compartido por toda la API; comprometer cualquier endpoint te da, de facto, el radio de acción de todos.

- **El feed global**, que es el access pattern que de verdad importa en el MVP, se resuelve con un índice secundario particionado ("sharded") y disperso ("sparse"): `GSI1PK=POSTS#<shard>`, un atributo que solo llega a existir en el ítem cuando el post está `published`. Esto no es una ocurrencia nuestra improvisada — es la mitigación estándar y documentada para el anti-patrón clásico de partición única en DynamoDB cuando necesitas un "todos los ítems ordenados por fecha". Con `N=5` particiones tenemos margen de sobra para cualquier pico de publicaciones que un proyecto de este tamaño vaya a ver en la vida real.

- **Cognito nos quita de encima toda la autenticación propia**: hashing de contraseñas, verificación de email, emisión y rotación de JWT. El Authorizer nativo de API Gateway valida cada token contra el user pool sin que tengamos que escribir ni una línea de verificación de firma nosotros mismos.

### Lo que aceptamos a cambio, sin maquillarlo

Ninguna decisión de arquitectura viene sin coste, y preferimos dejar constancia expresa de los trade-offs en vez de que parezcan descuidos:

- **El diseño single-table de DynamoDB tiene una curva de aprendizaje real.** No es SQL, y equivocarse en el diseño de una clave se paga después con migraciones de datos, no con un `ALTER TABLE`. La mitigación que aplicamos fue documentar cada patrón de acceso *antes* de escribir el código que lo usa (ver [Modelo de datos](#modelo-de-datos)) — pero el riesgo de diseño sigue estando ahí, y sería deshonesto decir que DynamoDB es "más simple" que una base relacional. Es distinto, no necesariamente más fácil.
- **El feed personalizado y el contador de likes son eventualmente consistentes**, porque dependen de un fan-out asíncrono disparado por DynamoDB Streams. Lo aceptamos porque el dominio lo permite perfectamente — a nadie le importa si un "me gusta" tarda 300 milisegundos en reflejarse en la pantalla de otra persona —, pero es una renuncia consciente a la consistencia fuerte, no algo que se nos escapara.
- **`dynamodb:LeadingKeys` no funciona como condición sobre `TransactWriteItems`.** Esto lo descubrimos escribiendo la función que permite cambiar de nombre de usuario (`update_profile`), que necesita mover de forma atómica dos ítems relacionados. La única forma de hacerlo es conceder permiso de transacción sobre la tabla completa, sin el acotamiento fino que sí tenemos en el resto de funciones. Lo compensamos manteniendo esa función deliberadamente aislada y estrecha — hace una sola cosa — pero es una excepción real a la regla de mínimo privilegio, y está documentada como tal, no escondida entre el resto del código.
- **El Authorizer JWT nativo de API Gateway no sabe nada de grupos de Cognito.** Verifica que el token es válido, pero no distingue un usuario normal de un administrador. Las dos rutas que necesitan ese matiz (`list_moderation_queue`, `resolve_report`) hacen la comprobación de grupo dentro del propio código de la función, leyendo el claim `cognito:groups` del token ya validado.

### Otras alternativas que se quedaron en el camino

- **Meter API Gateway delante de un backend en contenedores.** En la primera versión (con ECS) llegamos a plantearlo y lo descartamos: el ALB junto con WAF ya cubrían TLS, autenticación y limitación de tráfico sin coste adicional, así que añadir API Gateway ahí habría sido una capa de más sin beneficio real. Al pasar a serverless, la situación se invierte del todo: ahí sí, API Gateway es la pieza natural, con integración directa a Lambda sin necesidad de un Network Load Balancer ni de un VPC Link de por medio.
- **Aurora Serverless v2 como término medio.** Nos lo planteamos como una tercera vía: modelo relacional de verdad, con un escalado a casi cero parecido al de DynamoDB. Lo descartamos por la complejidad de gestionar el pool de conexiones desde Lambda (necesitarías RDS Proxy de por medio), que no nos parecía que compensara frente al ahorro marginal de coste a la escala de este proyecto.

---

## Modelo de datos

Una única tabla en DynamoDB (`communly-<environment>`), con dos índices secundarios globales. El fichero [`modules/dynamodb/dynamodb.tf`](./modules/dynamodb/dynamodb.tf) tiene la definición completa, comentada campo a campo.

| Necesidad | Clave |
|---|---|
| Perfil por `sub` o por `username` | `PK=USER#<sub>` o `PK=USERNAME#<username>`, `SK=PROFILE` |
| Post | `PK=POST#<id>`, `SK=META` |
| Feed global (particionado, disperso) | `GSI1PK=POSTS#<shard 0..4>`, `GSI1SK=PUBLISHED#<publishedAt>#<id>` — solo existe si `status=published` |
| Comentarios de un post | `PK=POST#<id>`, `SK=COMMENT#<ts>#<id>` |
| Posts / comentarios / likes de un usuario | `GSI2PK=USER#<sub>`, `GSI2SK=<TIPO>#<ts>#<id>` |
| Posts por tag | `GSI2PK=TAG#<tag>` |
| A quién sigue / quién le sigue | mismo ítem: tabla base (`FOLLOWING#`) proyectado también en GSI1 (`FOLLOWER#`) |
| Feed personalizado (fan-out) | `PK=USER#<sub>`, `SK=FEED#<ts>#<id>`, con TTL |
| Notificaciones | `PK=USER#<sub>`, `SK=NOTIFICATION#<ts>#<id>` |
| Cola de moderación (dispersa) | `GSI2PK=MODERATION#OPEN` — el atributo se elimina al resolver la denuncia |

`DynamoDB Streams`, en modo `NEW_AND_OLD_IMAGES`, alimenta dos funciones asíncronas: el **fan-out** del feed personalizado y las **notificaciones** por email al recibir un comentario. Cada una tiene su propia cola de mensajes fallidos (DLQ) y una política de reintentos acotada — si algo falla de forma persistente, no se reintenta para siempre, se aparta para revisión manual.

---

## Red y superficie de exposición

Esta sección merece existir por sí sola, porque su respuesta corta es poco habitual: **no hay red que gestionar.** No hay VPC, no hay subredes públicas ni privadas, no hay grupos de seguridad, no hay tablas de rutas. No es una omisión — es la consecuencia directa de haber elegido servicios totalmente gestionados en cada capa (Lambda, DynamoDB, API Gateway, Cognito) que no necesitan vivir dentro de una red privada para funcionar ni para comunicarse entre sí de forma segura.

Eso cambia por completo cómo pensamos la superficie de exposición:

- **El único punto de entrada público real es CloudFront.** Todo lo demás — API Gateway, los buckets de S3 — está diseñado para no ser accesible directamente. Los buckets de S3 solo aceptan lecturas desde CloudFront vía Origin Access Control; no hay ninguna política que permita acceso público directo a un bucket.
- **WAF se sitúa en el borde, delante de CloudFront**, no delante de cada servicio individual. Es la única capa que de verdad "mira" el tráfico en bruto antes de que llegue a cualquier otro sitio: managed rule groups contra patrones conocidos de ataque, y una regla de limitación de tasa por IP.
- **La comunicación entre Lambda y DynamoDB, o entre Lambda y S3, no atraviesa nunca la internet pública** — son llamadas a la API de AWS autenticadas con SigV4, dentro de la red interna de AWS. No necesitamos un VPC endpoint para "proteger" ese tráfico porque nunca sale a una red que haya que proteger.
- **No hay NAT Gateway, y por tanto no hay ninguna decisión de egress que tomar.** Ninguna de nuestras funciones necesita iniciar conexiones salientes hacia servicios de terceros fuera del propio ecosistema de AWS (SES para email, y nada más). Si en el futuro se necesitara llamar a una API externa desde una Lambda, esa sí sería la primera vez que nos plantearíamos meter la función dentro de una VPC con NAT — hoy no hace falta.

Dicho lo cual, la ausencia de red no significa ausencia de fronteras: las fronteras aquí son de identidad y de permisos (Cognito decidiendo quién eres, IAM decidiendo qué puedes tocar), no de topología de red. Es un modelo de seguridad distinto al de una arquitectura con VPC, no uno "más débil" — simplemente desplaza el control de la capa de red a la capa de identidad y permisos.

---

## Escalabilidad

Aquí también conviene separar "cómo escala en la práctica" de "cuáles son los límites reales que existen, aunque hoy estén lejos".

**Lambda escala invocando más copias de la función en paralelo**, no hay nada que nosotros tengamos que configurar para que eso ocurra: si de repente llegan mil peticiones a la vez, AWS lanza (dentro de los límites de concurrencia de la cuenta) mil ejecuciones simultáneas. Lo único que tuvimos que decidir por nuestra parte fue la memoria asignada a cada función, que también determina la CPU disponible — las funciones de lectura, más ligeras, usan 128 MB; no hay ninguna que necesite más por ahora.

**DynamoDB en modo on-demand asume automáticamente picos de tráfico** hasta el doble del máximo histórico reciente, y luego sigue escalando por encima de eso con algo más de margen de reacción. Para un proyecto de este tamaño, esto es más que suficiente sin ningún ajuste manual. El punto donde sí hay que prestar atención es el reparto de carga entre particiones: por eso el feed global está deliberadamente particionado en `N=5` shards en vez de depender de una única partición que reciba todas las lecturas y escrituras — es la mitigación concreta contra el cuello de botella que, si no se hiciera, aparecería primero.

**API Gateway** en el plan HTTP API admite decenas de miles de peticiones por segundo sin que nosotros hagamos nada; el único control que configuramos explícitamente es el *throttling* por defecto a nivel de stage, pensado para contener un abuso puntual, no para limitar el crecimiento normal.

**CloudFront** es, de hecho, la pieza que más contribuye a la escalabilidad real del sistema, aunque no es la más vistosa: al cachear en el borde las respuestas anónimas (el listado del feed, la lectura de un post), la inmensa mayoría del tráfico de lectura — que, recordemos, es el grueso del tráfico esperado — ni siquiera llega a invocar una Lambda ni a consultar DynamoDB. Escala prácticamente gratis, en el sentido de que escalarla no exige ninguna decisión de capacidad por nuestra parte.

**Dónde sí hay un límite que merece la pena nombrar:** los *cold starts* de Lambda. Si una función lleva un rato sin invocarse, la primera petición tarda algo más mientras AWS aprovisiona el entorno de ejecución. A la escala de este proyecto es irrelevante (unas decenas o cientos de milisegundos, en un runtime ligero como Python), pero si el tráfico creciera varios órdenes de magnitud y la latencia p99 empezara a importar de verdad, la palanca disponible es la concurrencia aprovisionada — no la hemos activado porque tiene un coste fijo, y ese coste fijo es exactamente lo que esta arquitectura existe para evitar mientras no haga falta.

---

## Entorno de laboratorio (`dev`) frente a producción

`envs/prod` y `envs/dev` instancian exactamente los mismos ocho módulos de Terraform — no hay un segundo conjunto de módulos "para dev". La diferencia está en unas pocas variables, declaradas explícitamente en `envs/dev/variables.tf`, que en `prod` ni existen ni se usan. La razón de fondo es que `dev` corre sobre una cuenta de laboratorio con **IAM restringido a un catálogo fijo de roles predefinidos** (no se puede `iam:CreateRole`), así que todo lo que en `prod` resolvemos creando un recurso IAM propio, en `dev` hay que resolverlo de otra forma o, sencillamente, aceptar que no está disponible.

| | `prod` | `dev` |
|---|---|---|
| Rol de cada Lambda | Uno propio por función, mínimo privilegio | Uno compartido (`studentLambdaExecutionRole`), sin aislamiento por función |
| Conexión Lambda↔DynamoDB Streams | Siempre activa | `enable_stream_triggers` (por defecto `true`, se pone a `false` si el rol compartido no tiene los permisos de Streams) |
| Envío de email por SES | Real | `mock_ses_notifications` (por defecto `true`): la Lambda de notificaciones **no llama a SES en absoluto**, solo registra en el log qué habría enviado — el registro de la notificación en DynamoDB se guarda igual |
| WAF delante de CloudFront | Siempre activo | `enable_waf` (por defecto `true`, se pone a `false` si el laboratorio no permite `wafv2:*`) |
| Despliegue del código de las Lambdas | Vía `app-deploy.yml` (GitHub Actions sube a S3, llama a `update-function-code`) | `manage_lambda_code_with_terraform` (por defecto `true`): Terraform empaqueta y sube el código directamente en el propio `apply`, sin S3 ni pipeline |
| Build y despliegue del frontend | Vía `app-deploy.yml` (`npm run build` + `aws s3 sync` + invalidación) | `manage_frontend_with_terraform` (por defecto `true`): un `null_resource` con `local-exec` ejecuta el mismo build+sync+invalidación dentro del `apply` — única excepción del proyecto al modelo declarativo puro de Terraform |
| CI/CD | GitHub Actions vía OIDC | Manual, en local, con la sesión SSO del laboratorio (ver `envs/dev/README.md`) |
| Región | `eu-west-1` | La que permita el laboratorio (verificar; no asumir `us-east-1` por defecto) |

Ninguno de estos interruptores tiene efecto en `prod`: cada uno vive detrás de una variable con valor por defecto que reproduce el comportamiento normal (`shared_execution_role_arn = null`, `enable_stream_triggers = true`, etc.), y `envs/prod` simplemente no las declara. Si algún día `dev` deja de tener estas restricciones, basta con no pasar esas variables (o ponerlas a su valor por defecto) para que se comporte exactamente igual que `prod`.

Documentado también, con más detalle operativo (comandos concretos, qué política de IAM pedir, cómo desplegar sin CI/CD), en [`envs/dev/README.md`](./envs/dev/README.md).



```
.
├── bootstrap/              # Terraform manual, una sola vez (tfstate backend + rol OIDC)
├── envs/
│   ├── prod/               # Entorno de producción
│   └── dev/                # Entorno de laboratorio/formación (IAM restringido a roles predefinidos)
├── modules/
│   ├── dynamodb/
│   ├── api-lambdas/        # 19 funciones, una por access pattern (generadas por for_each)
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
    └── app-deploy.yml      # build + deploy de las Lambdas y del frontend (push sobre app/**)
```

---

## Instrucciones de despliegue

### Requisitos previos

- Cuenta AWS con permisos de administrador (solo hace falta para el paso de `bootstrap/`).
- Terraform ≥ 1.7, y AWS CLI configurado localmente para ese primer paso.
- Un repositorio de GitHub con Actions habilitado.
- Una dirección de email verificable en SES (que arranca en modo sandbox, como todas las cuentas nuevas).

### Paso 0 — Bootstrap (manual, una sola vez)

```bash
cd bootstrap/
terraform init
terraform apply \
  -var="github_org=<tu-org-o-usuario>" \
  -var="github_repo=<nombre-del-repo>"
```

Este paso crea el bucket de estado remoto, la tabla de bloqueos, el proveedor OIDC de GitHub y el rol `communly-github-actions` con su permissions boundary. Guarda los outputs, los necesitas en el siguiente paso. El estado de este `apply` en concreto es **local** — no se sube al repositorio (así lo dice el `.gitignore`) — porque es precisamente el que crea el backend remoto que usará todo lo demás; cópialo a un sitio seguro por si acaso.

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
| `ALARM_EMAIL` | email que recibe las alarmas |

### Paso 2 — Primer despliegue de infraestructura (fase 1)

Un push a `main` que toque `envs/**` o `modules/**` dispara `infra.yml`. Con los valores por defecto (`communly.example.com`, `localhost:5173`) en `callback_urls`/`cors_allowed_origins`, este primer `apply` ya crea los ocho módulos completos.

> **Por qué hace falta una fase 2**: `callback_urls` de Cognito no puede depender del dominio de CloudFront sin cerrar un ciclo real en el grafo de dependencias de Terraform (está comentado en `envs/prod/main.tf`, justo junto a `module.cognito`). No es una limitación de nuestro diseño en particular — es una consecuencia inevitable de que el dominio final no se conoce hasta que la propia distribución existe.

### Paso 3 — Variables de fase 2

Con la infraestructura ya desplegada:

```bash
cd envs/prod && terraform output
```

Toma `cloudfront_domain_name`, `api_gateway_endpoint`, `cognito_user_pool_id`, `cognito_user_pool_client_id`, `cognito_hosted_ui_domain`, `frontend_bucket_name`, `images_bucket_name` y `alarms_topic_arn`, y con ellos:

1. Actualiza `var.callback_urls`, `var.logout_urls` y `var.cors_allowed_origins` con el dominio real de CloudFront, y vuelve a aplicar — este segundo `apply` solo actualiza el cliente de Cognito y el CORS de API Gateway, no recrea nada.
2. Añade el resto de variables de GitHub que faltaban: `LAMBDA_CODE_BUCKET`, `FRONTEND_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`, `API_BASE_URL` (`https://<dominio-cloudfront>/api`), `COGNITO_HOSTED_UI_DOMAIN`, `COGNITO_CLIENT_ID`, `FRONTEND_REDIRECT_URI`, `FRONTEND_LOGOUT_URI`.

### Paso 4 — Primer despliegue de la aplicación

Un push a `main` que toque `app/**` dispara `app-deploy.yml`: empaqueta y publica las 20 funciones Lambda (sustituyendo los placeholders que dejó Terraform) y construye/sincroniza el frontend con las variables `VITE_*` inyectadas en tiempo de build.

### Paso 5 — Lo que queda por hacer a mano

- **Confirmar la suscripción de SNS**: llega un correo a `ALARM_EMAIL` que hay que aceptar manualmente, o las alarmas no llegarán a ningún sitio.
- **SES sigue en modo sandbox** hasta que se pida salir de él: mientras tanto, solo se puede enviar correo a direcciones verificadas una por una en la consola.
- **Dar de alta al primer administrador**: `aws cognito-idp admin-add-user-to-group --user-pool-id <id> --username <email> --group-name admins` (el grupo se define en `modules/cognito/groups.tf`).

---

## Estimación de coste mensual

Separamos dos escenarios: coste con cero tráfico, y coste con el tráfico bajo-moderado que esperamos de un proyecto de portfolio. Tarifas de 2026 en us-east-1; en eu-west-1 puede haber entre un 10% y un 20% más.

| Servicio | En reposo | Con tráfico bajo-moderado |
|---|---|---|
| Lambda (20 funciones) | $0 | $0 (dentro de la capa gratuita permanente: 1M invocaciones + 400.000 GB-s/mes) |
| DynamoDB on-demand | ~$0,45 (almacenamiento + PITR) | ~$0,70 |
| API Gateway (HTTP API) | $0 | ~$0,07 |
| Cognito | $0 | $0 (nivel Essentials, hasta 10.000 MAU) |
| CloudFront | ~$1 | ~$10 |
| AWS WAF | ~$10 (fijo: Web ACL + reglas) | ~$10 |
| S3 (frontend + imágenes + código) | ~$1 | ~$3 |
| CloudWatch Logs y alarmas | ~$1 | ~$5 |
| SES | $0 | ~$1 |
| SNS / SQS | $0 | ~$1 |
| AWS Budgets | $0 | $0 |
| **TOTAL** | **≈ 12-13 $/mes** | **≈ 30-31 $/mes** |

Para poner esto en perspectiva: la arquitectura que descartamos (ECS Fargate + RDS + ALB + NAT) rondaba los 183 $/mes con tráfico bajo, y tenía un suelo fijo en reposo de unos 150 $/mes. Esta arquitectura reduce el coste en más de un 80%, y el motivo de fondo — pagar por uso en vez de pagar por capacidad reservada, para un patrón de tráfico que es rachas sobre silencio — es exactamente el argumento central de la [decisión arquitectónica](#decisión-arquitectónica). Es agradable cuando los números terminan confirmando la teoría.

También cambia qué partida manda en la factura. Antes era el NAT Gateway: un coste que existía por estar encendido, sin ninguna relación con el valor que aportaba al producto. Ahora son **CloudFront y WAF** — dos costes que sí están ahí por una razón que se puede defender delante de cualquiera: rendimiento de borde y seguridad perimetral.

---

## Seguridad

Preferimos explicar la seguridad como capas, porque así es como realmente está pensada, no como una lista suelta de features:

**Capa de borde.** WAF con managed rule groups (`CommonRuleSet` contra inyecciones y XSS genérico, `KnownBadInputsRuleSet` contra exploits conocidos) más una regla de limitación de tasa por IP, todo delante de CloudFront. Es la primera barrera, y actúa antes de que la petición llegue a ningún otro servicio.

**Capa de identidad.** Cognito es la única fuente de verdad para credenciales — nunca gestionamos ni almacenamos una contraseña nosotros mismos. El login de la SPA usa Authorization Code + PKCE, el flujo correcto para un cliente público que no puede guardar un secreto de forma segura (a diferencia de un backend, donde sí tendría sentido un client secret). El JWT Authorizer nativo de API Gateway valida cada token antes de que la petición llegue a cualquier Lambda.

**Capa de aplicación.** Cada una de las funciones Lambda tiene su propio rol de IAM, acotado por prefijo de partición de DynamoDB. Es la aplicación más literal posible del principio de mínimo privilegio: si una función solo necesita leer bajo `POST#*`, su rol no puede ni ver lo que hay bajo `USER#*`. La única excepción reconocida es `update_profile`, que por necesitar una transacción atómica entre dos ítems no puede acotarse de la misma forma — está documentado como excepción consciente, no oculto.

**Capa de datos.** Cifrado en reposo en DynamoDB y en los buckets de S3, cifrado en tránsito en todas partes (HTTPS forzado tanto en CloudFront como en API Gateway), y recuperación a un punto en el tiempo activada en la tabla. No gestionamos ningún secreto de base de datos porque, sencillamente, no existe: Cognito sustituye por completo esa necesidad.

**Capa de despliegue.** GitHub Actions no guarda ninguna credencial de larga duración: se autentica contra AWS vía OIDC, obteniendo credenciales temporales solo para la duración de cada ejecución, acotadas además por un permissions boundary que actúa como techo absoluto incluso si la política del rol tuviera algún error.

**Lo que esto no cubre, y hay que decirlo.** No hay ninguna herramienta de detección de amenazas en tiempo de ejecución (algo como GuardDuty), no hay escaneo automático de dependencias en el pipeline, y no hay ningún tipo de rate limiting por usuario autenticado más allá del límite por IP del WAF — alguien con una cuenta válida podría, en teoría, hacer un uso abusivo de la API dentro de los límites de su propio token. Para el alcance de este proyecto no nos pareció justificado, pero es una laguna real, no una que se nos haya pasado por alto sin más (ver [Mejoras futuras](#mejoras-futuras)).

## Observabilidad

- **Logs centralizados**: un grupo de logs por función Lambda (`modules/observability/log_groups.tf`), más los logs de acceso de API Gateway.
- **Alarmas activas**: errores por función Lambda, respuestas 5xx en API Gateway, throttling en DynamoDB, y mensajes acumulados en las colas de fallidos de `stream-consumers`. Todas notifican al mismo topic de SNS, que a su vez avisa por email.

## FinOps

- **Etiquetado**: `Project`, `Environment` y `Owner` se aplican vía `default_tags` en el provider (`envs/prod/providers.tf`), así que todo recurso que soporte etiquetas las recibe automáticamente, sin que tengamos que repetirlas recurso a recurso.
- **AWS Budgets**: documentado en la estimación de coste, pero todavía no está instanciado como recurso de Terraform — hoy es una cifra en una tabla, no una alarma real que se dispare sola. Lo dejamos anotado en [Mejoras futuras](#mejoras-futuras) en vez de darlo por hecho.

---

## Instrucciones de destrucción

```bash
cd envs/prod
terraform destroy
```

Antes de destruir un entorno real (no aplica si `environment != "prod"`), hay tres cosas que suelen bloquear el proceso si no se preparan antes:

1. **DynamoDB tiene protección contra borrado activada en producción** (`deletion_protection_enabled = true`). Hay que desactivarla primero, bien cambiando el flag y volviendo a aplicar, bien directamente con `aws dynamodb update-table --deletion-protection-enabled false`.
2. **Cognito tiene el mismo tipo de protección** (`deletion_protection = "ACTIVE"`). Se desactiva de forma equivalente, vía `aws cognito-idp update-user-pool`.
3. **Los buckets de S3 no vacíos bloquean el `destroy`.** O se vacían a mano (`aws s3 rm s3://<bucket> --recursive`), o se añade temporalmente `force_destroy = true` antes de destruir.

El `bootstrap/` (backend de estado + rol OIDC) se destruye aparte, al final, y solo si de verdad se quiere eliminar el proyecto por completo — no forma parte del ciclo normal de destruir/recrear el entorno:

```bash
cd bootstrap/
terraform destroy
```

---

## Limitaciones conocidas

Preferimos dejarlas escritas aquí a que las descubra otra persona sin avisar:

- **La moderación no termina la acción.** `resolve_report` marca una denuncia como resuelta, pero no borra el post denunciado ni sanciona a la cuenta que lo publicó — falta esa pieza final, y hoy es un paso manual.
- **El botón de "me gusta" no recuerda el estado anterior.** Arranca siempre en `false` en el frontend, aunque el usuario ya hubiera dado like antes de cargar la página; falta un access pattern de lectura que compruebe ese estado antes de pintar el botón.
- **AWS Budgets solo existe en la documentación, no en el código.** La cifra de coste está calculada y es correcta, pero no hay ninguna alarma de presupuesto real desplegada todavía.
- **`update_profile` tiene un permiso más amplio de lo que nos gustaría**, por la limitación real de `TransactWriteItems` ya explicada en la sección de seguridad.
- **No hay dominio propio.** Se usa el dominio por defecto de CloudFront (`*.cloudfront.net`); añadir uno propio implica un certificado ACM en `us-east-1` y configurar el alias, y no lo hemos hecho.
- **Consistencia eventual** en el feed personalizado y en el contador de likes, aceptada por diseño y ya justificada en la [decisión arquitectónica](#decisión-arquitectónica).

## Mejoras futuras

Esta lista está pensada como una hoja de ruta razonable si el proyecto siguiera adelante más allá de la entrega, ordenada más o menos por lo que aportaría antes en relación con lo que costaría:

**Corto plazo, coste bajo**
- Completar la acción real de moderación: que `resolve_report` pueda, opcionalmente, borrar el post o marcar la cuenta del autor como sancionada, en vez de solo cerrar la denuncia.
- Añadir el access pattern que falta para que "me gusta" recuerde su estado (`GetItem` sobre `PK=POST#<id>/SK=LIKE#<sub>` antes de pintar el botón).
- Instanciar `AWS Budgets` como recurso de Terraform, con una alarma real de coste mensual en vez de dejarlo solo en la documentación.
- Dominio propio con certificado ACM, para dejar de depender del dominio genérico de CloudFront — más una cuestión de imagen que técnica, pero relevante si esto se enseña a terceros.

**Medio plazo**
- Rate limiting por usuario autenticado, no solo por IP — probablemente lo más razonable sea un contador con TTL en la propia tabla, incrementado en cada escritura, en vez de añadir un servicio nuevo solo para esto.
- Trazabilidad distribuida con AWS X-Ray entre API Gateway, Lambda y DynamoDB, para poder ver de un vistazo dónde se va el tiempo en una petición lenta en vez de reconstruirlo a mano a partir de logs sueltos.
- Escaneo automático de dependencias en el pipeline de CI (tanto en el código Python de las Lambdas como en el `package.json` del frontend), para no depender de acordarnos de mirarlo manualmente.
- Un entorno de `staging` real entre `dev` y `prod`, reutilizando los mismos módulos con otra clave de estado — el diseño de `envs/` ya lo contempla, solo falta añadir la carpeta.

**Más ambicioso, si el proyecto creciera de verdad**
- Multi-región para el frontend y la capa de borde (CloudFront ya es global; lo que faltaría es una segunda región activa para Lambda/DynamoDB si la latencia para usuarios lejanos llegara a importar).
- Sustituir el envío directo por SES por una cola intermedia (SQS o EventBridge) delante de las notificaciones por email, para desacoplar aún más el pico de comentarios del límite de envío de SES.
- Tests de integración automatizados contra un entorno efímero desplegado y destruido en cada pull request, en vez de depender solo de pruebas manuales antes de cada release.
- Detección de amenazas en tiempo de ejecución (por ejemplo, GuardDuty) — hoy conscientemente fuera de alcance, mencionado también en el apartado de seguridad.
