from boto3.dynamodb.conditions import Key
from shared.dynamo import table
from shared.http import ok, err

_INTERNAL_KEYS = ("PK", "SK", "GSI2PK", "GSI2SK")


def handler(event, context):
    post_id = (event.get("pathParameters") or {}).get("postId")
    if not post_id:
        return err(400, "postId requerido")

    res = table.query(
        KeyConditionExpression=Key("PK").eq(f"POST#{post_id}") & Key("SK").begins_with("COMMENT#"),
        ScanIndexForward=True,
        Limit=100,
    )

    comments = [
        {k: v for k, v in item.items() if k not in _INTERNAL_KEYS}
        for item in res.get("Items", [])
    ]
    return ok({"comments": comments})
