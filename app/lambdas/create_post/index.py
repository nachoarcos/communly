import os
import json
import uuid
import hashlib
from datetime import datetime, timezone
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub

SHARD_COUNT = int(os.environ.get("FEED_SHARD_COUNT", "5"))
_INTERNAL_KEYS = ("PK", "SK", "GSI1PK", "GSI1SK", "GSI2PK", "GSI2SK")


def shard_for(post_id):
    # Distribucion estable: el mismo post_id siempre cae en el mismo shard.
    digest = hashlib.md5(post_id.encode()).hexdigest()
    return int(digest[:8], 16) % SHARD_COUNT


def handler(event, context):
    user_sub = get_user_sub(event)
    if not user_sub:
        return err(401, "No autenticado")

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return err(400, "JSON invalido")

    title = body.get("title")
    body_markdown = body.get("bodyMarkdown")
    status = body.get("status", "draft")

    if not title or not body_markdown:
        return err(400, "title y bodyMarkdown son obligatorios")
    if status not in ("draft", "published"):
        return err(400, "status debe ser draft o published")

    current = table.get_item(Key={"PK": f"USER#{user_sub}", "SK": "PROFILE"}).get("Item") or {}
    author_username = current.get("username")

    post_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    item = {
        "PK": f"POST#{post_id}",
        "SK": "META",
        "post_id": post_id,
        "author_sub": user_sub,
        # Denormalizado en escritura, mismo patron que el email en el
        # perfil: evita que el frontend tenga que resolver username por
        # cada post del feed. Si el autor cambia de username despues,
        # los posts ya publicados conservan el nombre de entonces (es
        # el trade-off aceptado de la denormalizacion).
        "author_username": author_username,
        "title": title,
        "body_markdown": body_markdown,
        "status": status,
        "created_at": now,
        "updated_at": now,
    }

    # Sparse por diseno: estas claves solo existen si el post nace ya
    # publicado. Un draft no las tiene y por tanto no aparece en ningun
    # indice de listado (ver modules/dynamodb/dynamodb.tf).
    if status == "published":
        item["published_at"] = now
        item["GSI1PK"] = f"POSTS#{shard_for(post_id)}"
        item["GSI1SK"] = f"PUBLISHED#{now}#{post_id}"
        item["GSI2PK"] = f"USER#{user_sub}"
        item["GSI2SK"] = f"POST#{now}#{post_id}"

    table.put_item(Item=item, ConditionExpression="attribute_not_exists(PK)")

    return ok({k: v for k, v in item.items() if k not in _INTERNAL_KEYS}, 201)
