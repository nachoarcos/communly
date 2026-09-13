import os
import boto3
from datetime import datetime, timezone
from botocore.exceptions import ClientError

TABLE_NAME = os.environ["TABLE_NAME"]
_table = boto3.resource("dynamodb").Table(TABLE_NAME)
_client = boto3.client("dynamodb")


def handler(event, context):
    attrs = event["request"]["userAttributes"]
    sub = attrs["sub"]
    email = attrs.get("email")
    username = attrs.get("custom:username")
    now = datetime.now(timezone.utc).isoformat()

    username_reserved = False
    if username:
        username_reserved = _try_reserve_username(sub, username, email, now)

    if not username_reserved:
        # O no se pidio username, o la reserva transaccional fallo por
        # una colision de ultima hora entre el chequeo best-effort de
        # pre_signup y este punto. El usuario de Cognito YA ESTA
        # creado y confirmado -- post_confirmation no puede deshacer
        # eso, asi que se degrada de forma controlada: perfil sin
        # username, marcado needs_username=True para que el cliente lo
        # resuelva en un paso posterior (endpoint update_profile,
        # pendiente de implementar).
        _table.put_item(
            Item={
                "PK": f"USER#{sub}",
                "SK": "PROFILE",
                "sub": sub,
                "username": None,
                "email": email,
                "created_at": now,
                "needs_username": True,
            }
        )

    return event


def _try_reserve_username(sub, username, email, now):
    user_item = {
        "PK": {"S": f"USER#{sub}"},
        "SK": {"S": "PROFILE"},
        "sub": {"S": sub},
        "username": {"S": username},
        "created_at": {"S": now},
    }
    if email:
        user_item["email"] = {"S": email}

    try:
        _client.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": TABLE_NAME,
                        "Item": user_item,
                        "ConditionExpression": "attribute_not_exists(PK)",
                    }
                },
                {
                    "Put": {
                        "TableName": TABLE_NAME,
                        "Item": {
                            "PK": {"S": f"USERNAME#{username}"},
                            "SK": {"S": "PROFILE"},
                            "sub": {"S": sub},
                            "username": {"S": username},
                            "created_at": {"S": now},
                        },
                        "ConditionExpression": "attribute_not_exists(PK)",
                    }
                },
            ]
        )
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "TransactionCanceledException":
            return False
        raise
