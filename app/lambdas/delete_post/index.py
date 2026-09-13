from datetime import datetime, timezone
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub


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
        return err(403, "Solo el autor puede borrar este post")

    now = datetime.now(timezone.utc).isoformat()

    # Borrado logico: se conserva el item (auditable), pero se marca
    # deleted_at y se elimina de TODOS los indices de listado (feed
    # global, posts del usuario) para que deje de ser visible en
    # cualquier consulta publica.
    table.update_item(
        Key={"PK": f"POST#{post_id}", "SK": "META"},
        UpdateExpression="SET deleted_at = :now REMOVE GSI1PK, GSI1SK, GSI2PK, GSI2SK",
        ExpressionAttributeValues={":now": now},
    )

    return ok({"postId": post_id, "deletedAt": now})
