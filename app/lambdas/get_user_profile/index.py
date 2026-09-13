from shared.dynamo import table
from shared.http import ok, err


def handler(event, context):
    username = (event.get("pathParameters") or {}).get("username")
    if not username:
        return err(400, "username requerido")

    res = table.get_item(Key={"PK": f"USERNAME#{username}", "SK": "PROFILE"})
    item = res.get("Item")
    if not item:
        return err(404, "Usuario no encontrado")

    return ok(
        {
            "sub": item.get("sub"),
            "username": item.get("username"),
            "bio": item.get("bio"),
            "avatarUrl": item.get("avatar_url"),
            "createdAt": item.get("created_at"),
        }
    )
