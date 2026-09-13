from shared.dynamo import table
from shared.http import ok, err

_INTERNAL_KEYS = ("PK", "SK", "GSI1PK", "GSI1SK", "GSI2PK", "GSI2SK")


def handler(event, context):
    post_id = (event.get("pathParameters") or {}).get("postId")
    if not post_id:
        return err(400, "postId requerido")

    res = table.get_item(Key={"PK": f"POST#{post_id}", "SK": "META"})
    item = res.get("Item")
    if not item or item.get("deleted_at"):
        return err(404, "Post no encontrado")

    return ok({k: v for k, v in item.items() if k not in _INTERNAL_KEYS})
