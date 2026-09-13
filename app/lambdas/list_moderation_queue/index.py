from boto3.dynamodb.conditions import Key
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import is_admin

_INTERNAL_KEYS = ("PK", "SK", "GSI2PK", "GSI2SK")


def handler(event, context):
    # El JWT Authorizer de API Gateway ya garantiza que hay una sesion
    # valida (auth_required = true); NO garantiza pertenencia al grupo
    # admins. Esa comprobacion es responsabilidad de este handler (ver
    # modules/api-gateway/routes.tf).
    if not is_admin(event):
        return err(403, "Requiere rol de administrador")

    res = table.query(
        IndexName="GSI2",
        KeyConditionExpression=Key("GSI2PK").eq("MODERATION#OPEN"),
        ScanIndexForward=True,  # denuncias mas antiguas primero
        Limit=50,
    )

    reports = [
        {k: v for k, v in item.items() if k not in _INTERNAL_KEYS}
        for item in res.get("Items", [])
    ]
    return ok({"reports": reports})
