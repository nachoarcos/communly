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

    method = event.get("requestContext", {}).get("http", {}).get("method", "")

    if method == "DELETE":
        table.delete_item(Key={"PK": f"POST#{post_id}", "SK": f"LIKE#{user_sub}"})
        return ok({"postId": post_id, "liked": False})

    if method in ("PUT", "POST"):
        now = datetime.now(timezone.utc).isoformat()
        table.put_item(
            Item={
                "PK": f"POST#{post_id}",
                "SK": f"LIKE#{user_sub}",
                "post_id": post_id,
                "user_sub": user_sub,
                "created_at": now,
                # Proyeccion para "posts que gustaron a un usuario".
                "GSI2PK": f"USER#{user_sub}",
                "GSI2SK": f"LIKE#{now}#{post_id}",
            }
        )
        return ok({"postId": post_id, "liked": True})

    return err(405, "Metodo no soportado")
