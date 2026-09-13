from boto3.dynamodb.conditions import Key
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub

_INTERNAL_KEYS = ("PK", "SK")


def handler(event, context):
    user_sub = get_user_sub(event)
    if not user_sub:
        return err(401, "No autenticado")

    res = table.query(
        KeyConditionExpression=Key("PK").eq(f"USER#{user_sub}") & Key("SK").begins_with("NOTIFICATION#"),
        ScanIndexForward=False,
        Limit=20,
    )

    items = [
        {k: v for k, v in item.items() if k not in _INTERNAL_KEYS}
        for item in res.get("Items", [])
    ]
    return ok({"notifications": items})
