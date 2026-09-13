from datetime import datetime, timezone
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub


def handler(event, context):
    follower_sub = get_user_sub(event)
    if not follower_sub:
        return err(401, "No autenticado")

    username = (event.get("pathParameters") or {}).get("username")
    if not username:
        return err(400, "username requerido")

    profile = table.get_item(Key={"PK": f"USERNAME#{username}", "SK": "PROFILE"}).get("Item")
    if not profile:
        return err(404, "Usuario no encontrado")
    followee_sub = profile["sub"]

    if followee_sub == follower_sub:
        return err(400, "No puedes seguirte a ti mismo")

    method = event.get("requestContext", {}).get("http", {}).get("method", "")

    if method == "DELETE":
        table.delete_item(
            Key={"PK": f"USER#{follower_sub}", "SK": f"FOLLOWING#{followee_sub}"}
        )
        return ok({"username": username, "following": False})

    if method in ("PUT", "POST"):
        now = datetime.now(timezone.utc).isoformat()
        # Un unico item resuelve las dos consultas: "a quien sigo"
        # (tabla base, PK/SK) y "quien me sigue" (GSI1, proyectado
        # sobre el usuario seguido) -- mismo patron que la tabla de
        # claves original.
        table.put_item(
            Item={
                "PK": f"USER#{follower_sub}",
                "SK": f"FOLLOWING#{followee_sub}",
                "follower_sub": follower_sub,
                "followee_sub": followee_sub,
                "created_at": now,
                "GSI1PK": f"USER#{followee_sub}",
                "GSI1SK": f"FOLLOWER#{now}#{follower_sub}",
            }
        )
        return ok({"username": username, "following": True})

    return err(405, "Metodo no soportado")
