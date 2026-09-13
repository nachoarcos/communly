locals {
  name_prefix = "${var.project_name}-${var.environment}"

  table_arn = var.dynamodb_table_arn
  gsi1_arn  = "${var.dynamodb_table_arn}/index/GSI1"
  gsi2_arn  = "${var.dynamodb_table_arn}/index/GSI2"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
  }

  # ---------------------------------------------------------------------
  # Un objeto por access pattern. Cada entrada genera:
  #  - una funcion Lambda independiente (lambda.tf)
  #  - un rol IAM propio con solo los permisos listados en "statements"
  #  - metadatos (http_method/http_path/auth_required/admin_only) que
  #    consume el modulo api-gateway para construir las rutas y decidir
  #    si aplica el Cognito Authorizer.
  #
  # "leading_keys" en un statement es un prefijo ESTATICO (p.ej. "POST#*"),
  # nunca depende del usuario que llama: el rol de ejecucion es fijo, no
  # el del invocador. El filtrado por "solo mis propios datos" (feed,
  # notificaciones) se hace en el handler leyendo el sub del JWT.
  # ---------------------------------------------------------------------
  functions = {

    get_user_profile = {
      description   = "Perfil publico de un usuario por username"
      memory        = 128
      timeout       = 5
      http_method   = ["GET"]
      http_path     = "/users/{username}"
      auth_required = false
      admin_only    = false
      statements = [
        { sid = "GetProfile", actions = ["dynamodb:GetItem"], resources = [local.table_arn], leading_keys = ["USERNAME#*"] }
      ]
    }

    list_posts = {
      description   = "Feed global paginado (Query sobre los N shards de GSI1)"
      memory        = 128
      timeout       = 10
      http_method   = ["GET"]
      http_path     = "/posts"
      auth_required = false
      admin_only    = false
      statements = [
        { sid = "QueryGlobalFeedShards", actions = ["dynamodb:Query"], resources = [local.gsi1_arn], leading_keys = ["POSTS#*"] }
      ]
    }

    get_post = {
      description   = "Post individual + su metadata"
      memory        = 128
      timeout       = 5
      http_method   = ["GET"]
      http_path     = "/posts/{postId}"
      auth_required = false
      admin_only    = false
      statements = [
        { sid = "GetPost", actions = ["dynamodb:GetItem"], resources = [local.table_arn], leading_keys = ["POST#*"] }
      ]
    }

    list_post_comments = {
      description   = "Comentarios de un post"
      memory        = 128
      timeout       = 10
      http_method   = ["GET"]
      http_path     = "/posts/{postId}/comments"
      auth_required = false
      admin_only    = false
      statements = [
        { sid = "QueryComments", actions = ["dynamodb:Query"], resources = [local.table_arn], leading_keys = ["POST#*"] }
      ]
    }

    list_user_posts = {
      description   = "Posts publicados por un usuario"
      memory        = 128
      timeout       = 10
      http_method   = ["GET"]
      http_path     = "/users/{username}/posts"
      auth_required = false
      admin_only    = false
      statements = [
        { sid = "ResolveUsername", actions = ["dynamodb:GetItem"], resources = [local.table_arn], leading_keys = ["USERNAME#*"] },
        { sid = "QueryUserPosts", actions = ["dynamodb:Query"], resources = [local.gsi2_arn], leading_keys = ["USER#*"] }
      ]
    }

    list_posts_by_tag = {
      description   = "Posts filtrados por tag"
      memory        = 128
      timeout       = 10
      http_method   = ["GET"]
      http_path     = "/tags/{tag}/posts"
      auth_required = false
      admin_only    = false
      statements = [
        { sid = "QueryPostsByTag", actions = ["dynamodb:Query"], resources = [local.gsi2_arn], leading_keys = ["TAG#*"] }
      ]
    }

    list_user_feed = {
      description   = "Feed personalizado del usuario autenticado (filtrado por sub en el handler)"
      memory        = 128
      timeout       = 10
      http_method   = ["GET"]
      http_path     = "/me/feed"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "QueryOwnFeed", actions = ["dynamodb:Query"], resources = [local.table_arn], leading_keys = ["USER#*"] }
      ]
    }

    list_user_notifications = {
      description   = "Notificaciones del usuario autenticado"
      memory        = 128
      timeout       = 10
      http_method   = ["GET"]
      http_path     = "/me/notifications"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "QueryOwnNotifications", actions = ["dynamodb:Query"], resources = [local.table_arn], leading_keys = ["USER#*"] }
      ]
    }

    get_own_profile = {
      description   = "Perfil propio del usuario autenticado (incluye needs_username)"
      memory        = 128
      timeout       = 5
      http_method   = ["GET"]
      http_path     = "/me/profile"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "ReadOwnProfile", actions = ["dynamodb:GetItem"], resources = [local.table_arn], leading_keys = ["USER#*"] }
      ]
    }

    update_profile = {
      description   = "Actualiza el perfil del usuario autenticado (bio, avatar, username)"
      memory        = 128
      timeout       = 10
      http_method   = ["PUT"]
      http_path     = "/me/profile"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "ReadOwnProfile", actions = ["dynamodb:GetItem"], resources = [local.table_arn], leading_keys = ["USER#*"] },
        { sid = "UpdateOwnProfile", actions = ["dynamodb:UpdateItem"], resources = [local.table_arn], leading_keys = ["USER#*"] },
        # dynamodb:LeadingKeys NO es una condition key soportada para
        # TransactWriteItems (a diferencia de PutItem/GetItem/
        # UpdateItem/BatchWriteItem): esta accion se autoriza sobre
        # toda la tabla. Es la razon por la que el cambio de username
        # vive en una Lambda aislada y estrecha, no compartiendo
        # permisos con otras.
        { sid = "TransactWriteUsername", actions = ["dynamodb:TransactWriteItems"], resources = [local.table_arn], leading_keys = null }
      ]
    }

    create_post = {
      description   = "Crea un post (draft o published)"
      memory        = 128
      timeout       = 10
      http_method   = ["POST"]
      http_path     = "/posts"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "ReadOwnProfile", actions = ["dynamodb:GetItem"], resources = [local.table_arn], leading_keys = ["USER#*"] },
        { sid = "PutPost", actions = ["dynamodb:PutItem"], resources = [local.table_arn], leading_keys = ["POST#*"] }
      ]
    }

    update_post = {
      description   = "Edita un post (verifica autoria comparando cognito_sub en el handler)"
      memory        = 128
      timeout       = 10
      http_method   = ["PUT"]
      http_path     = "/posts/{postId}"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "UpdatePost", actions = ["dynamodb:GetItem", "dynamodb:UpdateItem"], resources = [local.table_arn], leading_keys = ["POST#*"] }
      ]
    }

    delete_post = {
      description   = "Borrado logico de un post (verifica autoria en el handler)"
      memory        = 128
      timeout       = 10
      http_method   = ["DELETE"]
      http_path     = "/posts/{postId}"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "SoftDeletePost", actions = ["dynamodb:GetItem", "dynamodb:UpdateItem"], resources = [local.table_arn], leading_keys = ["POST#*"] }
      ]
    }

    create_comment = {
      description   = "Crea un comentario en un post"
      memory        = 128
      timeout       = 10
      http_method   = ["POST"]
      http_path     = "/posts/{postId}/comments"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "ReadOwnProfile", actions = ["dynamodb:GetItem"], resources = [local.table_arn], leading_keys = ["USER#*"] },
        { sid = "PutComment", actions = ["dynamodb:PutItem"], resources = [local.table_arn], leading_keys = ["POST#*"] }
      ]
    }

    toggle_like = {
      description   = "Da o quita like a un post (PUT/DELETE sobre el mismo item)"
      memory        = 128
      timeout       = 5
      http_method   = ["PUT", "DELETE"]
      http_path     = "/posts/{postId}/likes"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "ToggleLike", actions = ["dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem"], resources = [local.table_arn], leading_keys = ["POST#*"] }
      ]
    }

    toggle_follow = {
      description   = "Sigue o deja de seguir a un usuario"
      memory        = 128
      timeout       = 5
      http_method   = ["PUT", "DELETE"]
      http_path     = "/users/{username}/follow"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "ResolveUsername", actions = ["dynamodb:GetItem"], resources = [local.table_arn], leading_keys = ["USERNAME#*"] },
        { sid = "ToggleFollow", actions = ["dynamodb:PutItem", "dynamodb:DeleteItem"], resources = [local.table_arn], leading_keys = ["USER#*"] }
      ]
    }

    request_image_upload = {
      description   = "Registra la imagen y devuelve una URL prefirmada de S3"
      memory        = 128
      timeout       = 5
      http_method   = ["POST"]
      http_path     = "/posts/{postId}/images"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "RegisterImageItem", actions = ["dynamodb:PutItem"], resources = [local.table_arn], leading_keys = ["POST#*"] },
        { sid = "PresignUpload", actions = ["s3:PutObject"], resources = ["${var.images_bucket_arn}/*"], leading_keys = null }
      ]
    }

    report_post = {
      description   = "Crea una denuncia sobre un post"
      memory        = 128
      timeout       = 5
      http_method   = ["POST"]
      http_path     = "/posts/{postId}/reports"
      auth_required = true
      admin_only    = false
      statements = [
        { sid = "PutReport", actions = ["dynamodb:PutItem"], resources = [local.table_arn], leading_keys = ["POST#*"] }
      ]
    }

    list_moderation_queue = {
      description   = "Lista las denuncias abiertas (solo administradores)"
      memory        = 128
      timeout       = 10
      http_method   = ["GET"]
      http_path     = "/admin/moderation"
      auth_required = true
      admin_only    = true
      statements = [
        { sid = "QueryOpenReports", actions = ["dynamodb:Query"], resources = [local.gsi2_arn], leading_keys = ["MODERATION#*"] }
      ]
    }

    resolve_report = {
      description   = "Resuelve una denuncia (elimina GSI2PK, la saca de la cola)"
      memory        = 128
      timeout       = 10
      http_method   = ["POST"]
      http_path     = "/admin/reports/{reportId}/resolve"
      auth_required = true
      admin_only    = true
      statements = [
        { sid = "ResolveReport", actions = ["dynamodb:UpdateItem"], resources = [local.table_arn], leading_keys = ["POST#*"] }
      ]
    }
  }
}
