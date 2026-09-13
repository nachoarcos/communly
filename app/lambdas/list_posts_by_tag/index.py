from boto3.dynamodb.conditions import Key
from shared.dynamo import table
from shared.http import ok, err

_INTERNAL_KEYS = ("PK", "SK", "GSI1PK", "GSI1SK", "GSI2PK", "GSI2SK")


def handler(event, context):
    tag = (event.get("pathParameters") or {}).get("tag")
    if not tag:
        return err(400, "tag requerido")

    res = table.query(
        IndexName="GSI2",
        KeyConditionExpression=Key("GSI2PK").eq(f"TAG#{tag}") & Key("GSI2SK").begins_with("POST#"),
        ScanIndexForward=False,
        Limit=20,
    )

    posts = [
        {k: v for k, v in item.items() if k not in _INTERNAL_KEYS}
        for item in res.get("Items", [])
    ]
    return ok({"posts": posts})
