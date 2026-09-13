from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub

_INTERNAL_KEYS = ("PK", "SK")


def handler(event, context):
    user_sub = get_user_sub(event)
    if not user_sub:
        return err(401, "No autenticado")

    item = table.get_item(Key={"PK": f"USER#{user_sub}", "SK": "PROFILE"}).get("Item")
    if not item:
        return err(404, "Perfil no encontrado")

    return ok({k: v for k, v in item.items() if k not in _INTERNAL_KEYS})
