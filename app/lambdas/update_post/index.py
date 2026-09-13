import os
import json
import hashlib
from datetime import datetime, timezone
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub

SHARD_COUNT = int(os.environ.get("FEED_SHARD_COUNT", "5"))
_INTERNAL_KEYS = ("PK", "SK", "GSI1PK", "GSI1SK", "GSI2PK", "GSI2SK")
MAX_TAGS = 10


def shard_for(post_id):
    digest = hashlib.md5(post_id.encode()).hexdigest()
    return int(digest[:8], 16) % SHARD_COUNT


def normalize_tags(raw_tags):
    if not isinstance(raw_tags, list):
        return None
    seen = []
    for t in raw_tags:
        tag = str(t).strip().lower()
        if tag and tag not in seen:
            seen.append(tag)
    return seen[:MAX_TAGS]


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

    # None si el body no toca los tags (se mantienen los actuales);
    # una lista (incluso vacia) si el body SI los envia.
    incoming_tags = normalize_tags(body.get("tags"))
    current_tags = current.get("tags", [])
    new_tags = incoming_tags if incoming_tags is not None else current_tags
    if incoming_tags is not None:
        set_parts.append("tags = :tags")
        values[":tags"] = new_tags

    new_status = body.get("status")
    was_published = current.get("status") == "published"
    final_status = new_status or current.get("status")
    original_created_at = current.get("created_at", now)

    # GSI2 (posts del autor, incluidos borradores) se fija SIEMPRE,
    # de forma idempotente -- tambien cubre posts creados antes de
    # este cambio de diseno que todavia no lo tuvieran. Usa el
    # created_at ORIGINAL (no "now"): editar un post no debe cambiar
    # su posicion cronologica en /me/posts cada vez que se guarda.
    set_parts += ["GSI2PK = :gsi2pk", "GSI2SK = :gsi2sk"]
    values[":gsi2pk"] = f"USER#{user_sub}"
    values[":gsi2sk"] = f"POST#{original_created_at}#{post_id}"

    if new_status == "published" and not was_published:
        # draft -> published: entra en el feed global (GSI1). GSI2 ya
        # queda fijado arriba en cualquier caso.
        set_parts += ["#status = :status", "published_at = :now", "GSI1PK = :gsi1pk", "GSI1SK = :gsi1sk"]
        names["#status"] = "status"
        values[":status"] = "published"
        values[":gsi1pk"] = f"POSTS#{shard_for(post_id)}"
        values[":gsi1sk"] = f"PUBLISHED#{now}#{post_id}"
    elif new_status == "draft" and was_published:
        # published -> draft: sale del feed global (GSI1). GSI2 se
        # mantiene: el autor sigue viendo el post en /me/posts.
        set_parts.append("#status = :status")
        names["#status"] = "status"
        values[":status"] = "draft"
        remove_parts += ["GSI1PK", "GSI1SK"]
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

    # Reconciliacion de TAG#: solo deben existir items TAG# si el post
    # esta publicado tras esta actualizacion (mismo criterio sparse que
    # GSI1). Se compara el conjunto ANTES (solo si ya estaba publicado)
    # con el conjunto DESPUES (solo si sigue/pasa a estar publicado), y
    # se anaden/borran unicamente las diferencias.
    previous_tags = set(current.get("tags", [])) if was_published else set()
    desired_tags = set(new_tags) if final_status == "published" else set()

    for tag in previous_tags - desired_tags:
        table.delete_item(Key={"PK": f"POST#{post_id}", "SK": f"TAG#{tag}"})

    for tag in desired_tags - previous_tags:
        table.put_item(
            Item={
                "PK": f"POST#{post_id}",
                "SK": f"TAG#{tag}",
                "post_id": post_id,
                "tag": tag,
                "title": updated.get("title", current.get("title")),
                "author_username": current.get("author_username"),
                "author_avatar_url": current.get("author_avatar_url"),
                "published_at": updated.get("published_at", now),
                "GSI2PK": f"TAG#{tag}",
                "GSI2SK": f"POST#{updated.get('published_at', now)}#{post_id}",
            }
        )

    return ok({k: v for k, v in updated.items() if k not in _INTERNAL_KEYS})
