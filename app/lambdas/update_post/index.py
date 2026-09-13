import os
import json
import hashlib
from datetime import datetime, timezone
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub

SHARD_COUNT = int(os.environ.get("FEED_SHARD_COUNT", "5"))
_INTERNAL_KEYS = ("PK", "SK", "GSI1PK", "GSI1SK", "GSI2PK", "GSI2SK")


def shard_for(post_id):
    digest = hashlib.md5(post_id.encode()).hexdigest()
    return int(digest[:8], 16) % SHARD_COUNT


def handler(event, context):
    user_sub = get_user_sub(event)
    if not user_sub:
        return err(401, "No autenticado")

    post_id = (event.get("pathParameters") or {}).get("postId")
    if not post_id:
        return err(400, "postId requerido")

    current = table.get_item(Key={"PK": f"POST#{post_id}", "SK": "META"}).get("Item")
    if not current or current.get("deleted_at"):
        return err(404, "Post no encontrado")
    if current.get("author_sub") != user_sub:
        return err(403, "Solo el autor puede editar este post")

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return err(400, "JSON invalido")

    now = datetime.now(timezone.utc).isoformat()
    set_parts = ["updated_at = :now"]
    remove_parts = []
    values = {":now": now}
    names = {}

    if "title" in body:
        set_parts.append("#title = :title")
        names["#title"] = "title"
        values[":title"] = body["title"]

    if "bodyMarkdown" in body:
        set_parts.append("body_markdown = :body_markdown")
        values[":body_markdown"] = body["bodyMarkdown"]

    new_status = body.get("status")
    was_published = current.get("status") == "published"

    if new_status == "published" and not was_published:
        # draft -> published: entra en el feed global y en los posts
        # del usuario (ver create_post.py para la misma logica de shard).
        set_parts += ["#status = :status", "published_at = :now", "GSI1PK = :gsi1pk", "GSI1SK = :gsi1sk", "GSI2PK = :gsi2pk", "GSI2SK = :gsi2sk"]
        names["#status"] = "status"
        values[":status"] = "published"
        values[":gsi1pk"] = f"POSTS#{shard_for(post_id)}"
        values[":gsi1sk"] = f"PUBLISHED#{now}#{post_id}"
        values[":gsi2pk"] = f"USER#{user_sub}"
        values[":gsi2sk"] = f"POST#{now}#{post_id}"
    elif new_status == "draft" and was_published:
        # published -> draft: sale de todos los indices de listado.
        set_parts.append("#status = :status")
        names["#status"] = "status"
        values[":status"] = "draft"
        remove_parts += ["GSI1PK", "GSI1SK", "GSI2PK", "GSI2SK"]
    # Si el status no cambia (published->published o draft->draft), no
    # se toca GSI1SK: editar el contenido no debe alterar la posicion
    # cronologica del post en el feed.

    expr = "SET " + ", ".join(set_parts)
    if remove_parts:
        expr += " REMOVE " + ", ".join(remove_parts)

    update_kwargs = {
        "Key": {"PK": f"POST#{post_id}", "SK": "META"},
        "UpdateExpression": expr,
        "ExpressionAttributeValues": values,
        "ReturnValues": "ALL_NEW",
    }
    if names:
        update_kwargs["ExpressionAttributeNames"] = names

    res = table.update_item(**update_kwargs)
    updated = res.get("Attributes", {})

    return ok({k: v for k, v in updated.items() if k not in _INTERNAL_KEYS})
