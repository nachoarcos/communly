import json
import re
from datetime import datetime, timezone
import boto3
from botocore.exceptions import ClientError
from shared.dynamo import table, TABLE_NAME
from shared.http import ok, err
from shared.auth import get_user_sub

_client = boto3.client("dynamodb")
USERNAME_RE = re.compile(r"^[a-z0-9_]{3,30}$")
_INTERNAL_KEYS = ("PK", "SK")


def handler(event, context):
    user_sub = get_user_sub(event)
    if not user_sub:
        return err(401, "No autenticado")

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return err(400, "JSON invalido")

    current = table.get_item(Key={"PK": f"USER#{user_sub}", "SK": "PROFILE"}).get("Item")
    if not current:
        return err(404, "Perfil no encontrado")

    new_username = body.get("username")
    bio = body.get("bio")
    avatar_url = body.get("avatarUrl")
    now = datetime.now(timezone.utc).isoformat()
    current_username = current.get("username")

    if new_username and new_username != current_username:
        if not USERNAME_RE.match(new_username):
            return err(400, "El username debe tener 3-30 caracteres (a-z, 0-9, _)")

        reserved, error_message = _rename_username(
            user_sub, current_username, new_username, bio, avatar_url, now
        )
        if not reserved:
            return err(409, error_message)
    else:
        # No cambia el username: UpdateItem simple, sin transaccion.
        set_parts = ["updated_at = :now"]
        values = {":now": now}
        if bio is not None:
            set_parts.append("bio = :bio")
            values[":bio"] = bio
        if avatar_url is not None:
            set_parts.append("avatar_url = :avatar_url")
            values[":avatar_url"] = avatar_url

        table.update_item(
            Key={"PK": f"USER#{user_sub}", "SK": "PROFILE"},
            UpdateExpression="SET " + ", ".join(set_parts),
            ExpressionAttributeValues=values,
        )

    updated = table.get_item(Key={"PK": f"USER#{user_sub}", "SK": "PROFILE"}).get("Item", {})
    return ok({k: v for k, v in updated.items() if k not in _INTERNAL_KEYS})


def _rename_username(user_sub, old_username, new_username, bio, avatar_url, now):
    """
    Libera el username antiguo (si existia; puede ser None si el
    usuario llego aqui con needs_username=True) y reserva el nuevo en
    una unica transaccion, a la vez que actualiza el perfil.
    """
    items = []

    if old_username:
        items.append(
            {
                "Delete": {
                    "TableName": TABLE_NAME,
                    "Key": {"PK": {"S": f"USERNAME#{old_username}"}, "SK": {"S": "PROFILE"}},
                    # Seguridad extra: solo se libera si de verdad
                    # pertenecia a este usuario.
                    "ConditionExpression": "sub = :sub",
                    "ExpressionAttributeValues": {":sub": {"S": user_sub}},
                }
            }
        )

    items.append(
        {
            "Put": {
                "TableName": TABLE_NAME,
                "Item": {
                    "PK": {"S": f"USERNAME#{new_username}"},
                    "SK": {"S": "PROFILE"},
                    "sub": {"S": user_sub},
                    "username": {"S": new_username},
                    "created_at": {"S": now},
                },
                "ConditionExpression": "attribute_not_exists(PK)",
            }
        }
    )

    set_parts = ["username = :username", "updated_at = :now"]
    values = {":username": {"S": new_username}, ":now": {"S": now}}
    if bio is not None:
        set_parts.append("bio = :bio")
        values[":bio"] = {"S": bio}
    if avatar_url is not None:
        set_parts.append("avatar_url = :avatar_url")
        values[":avatar_url"] = {"S": avatar_url}

    items.append(
        {
            "Update": {
                "TableName": TABLE_NAME,
                "Key": {"PK": {"S": f"USER#{user_sub}"}, "SK": {"S": "PROFILE"}},
                # needs_username se limpia siempre que se fija un
                # username, tanto si es la primera vez (viniendo de la
                # degradacion de post_confirmation) como si es un
                # cambio posterior.
                "UpdateExpression": "SET " + ", ".join(set_parts) + " REMOVE needs_username",
                "ExpressionAttributeValues": values,
            }
        }
    )

    try:
        _client.transact_write_items(TransactItems=items)
        return True, None
    except ClientError as e:
        if e.response["Error"]["Code"] == "TransactionCanceledException":
            return False, "Ese nombre de usuario ya esta en uso"
        raise
