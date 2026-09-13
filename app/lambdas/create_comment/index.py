import json
import uuid
from datetime import datetime, timezone
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub

_INTERNAL_KEYS = ("PK", "SK", "GSI2PK", "GSI2SK")


def handler(event, context):
    user_sub = get_user_sub(event)
    if not user_sub:
        return err(401, "No autenticado")

    post_id = (event.get("pathParameters") or {}).get("postId")
    if not post_id:
        return err(400, "postId requerido")

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return err(400, "JSON invalido")

    comment_body = body.get("body")
    if not comment_body:
        return err(400, "body es obligatorio")

    comment_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    current = table.get_item(Key={"PK": f"USER#{user_sub}", "SK": "PROFILE"}).get("Item") or {}

    item = {
        "PK": f"POST#{post_id}",
        "SK": f"COMMENT#{now}#{comment_id}",
        "comment_id": comment_id,
        "post_id": post_id,
        "author_sub": user_sub,
        "author_username": current.get("username"),
        "author_avatar_url": current.get("avatar_url"),
        "body": comment_body,
        "created_at": now,
        # Proyeccion para "comentarios de un usuario".
        "GSI2PK": f"USER#{user_sub}",
        "GSI2SK": f"COMMENT#{now}#{comment_id}",
    }

    # DynamoDB Streams (INSERT, SK begins_with COMMENT#) dispara la
    # Lambda de notificaciones por email al autor del post (ver
    # app/stream-consumers/notifications).
    table.put_item(Item=item)

    return ok({k: v for k, v in item.items() if k not in _INTERNAL_KEYS}, 201)
