resource "aws_dynamodb_table" "communly" {
  name         = "${var.project_name}-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "PK"
  range_key = "SK"

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }

  # -------------------------------------------------------------------------
  # GSI1
  # - Ultimos posts publicados (feed global, SHARDED y SPARSE)
  #     GSI1PK = POSTS#<shard 0..N-1>              (solo si status = published)
  #     GSI1SK = PUBLISHED#<publishedAt>#<postId>
  # - Seguidores de un usuario (orden cronologico, mas reciente primero)
  #     GSI1PK = USER#<sub>
  #     GSI1SK = FOLLOWER#<createdAt>#<followerSub>
  # -------------------------------------------------------------------------
  attribute {
    name = "GSI1PK"
    type = "S"
  }
  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  # -------------------------------------------------------------------------
  # GSI2
  # - Posts / comentarios / likes de un usuario, posts por tag
  # - Cola de moderacion (SPARSE: se elimina GSI2PK al resolver la denuncia)
  #     GSI2PK = MODERATION#OPEN
  #     GSI2SK = <createdAt>#POST#<postId>#REPORT#<reportId>
  # -------------------------------------------------------------------------
  attribute {
    name = "GSI2PK"
    type = "S"
  }
  attribute {
    name = "GSI2SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI2"
    hash_key        = "GSI2PK"
    range_key       = "GSI2SK"
    projection_type = "ALL"
  }

  # TTL: usado en FEED (fan-out) y NOTIFICATION
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Streams: fan-out de feed (POST publicado) y notificaciones (COMMENT creado)
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  # Proteccion contra destroy accidental: activa solo en prod
  deletion_protection_enabled = var.environment == "prod" ? true : false

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
  }
}
