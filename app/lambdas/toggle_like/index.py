from datetime import datetime, timezone
from botocore.exceptions import ClientError
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub


def handler(event, context):
    user_sub = get_user_sub(event)
    if not user_sub:
        return err(401, "No autenticado")

    post_id = (event.get("pathParameters") or {}).get("postId")
    if not post_id:
        return err(400, "postId requerido")

    method = event.get("requestContext", {}).get("http", {}).get("method", "")

    if method == "DELETE":
        # ReturnValues=ALL_OLD: solo si de verdad habia un like que
        # borrar se decrementa el contador. Si el usuario pulsa
        # "quitar like" dos veces seguidas, la segunda vez no hay nada
        # que borrar y el contador no baja de mas.
        res = table.delete_item(
            Key={"PK": f"POST#{post_id}", "SK": f"LIKE#{user_sub}"},
            ReturnValues="ALL_OLD",
        )
        if res.get("Attributes"):
            table.update_item(
                Key={"PK": f"POST#{post_id}", "SK": "META"},
                UpdateExpression="ADD like_count :minus_one",
                ExpressionAttributeValues={":minus_one": -1},
            )
        return ok({"postId": post_id, "liked": False})

    if method in ("PUT", "POST"):
        now = datetime.now(timezone.utc).isoformat()
        try:
            # ConditionExpression: solo incrementa el contador si el
            # like es NUEVO. Sin esto, pulsar "me gusta" varias veces
            # seguidas (o un doble-click accidental en el frontend)
            # incrementaria el contador cada vez, aunque el like en si
            # sea el mismo (PutItem sin condicion es idempotente para
            # el registro, pero no lo seria para el contador).
            table.put_item(
                Item={
                    "PK": f"POST#{post_id}",
                    "SK": f"LIKE#{user_sub}",
                    "post_id": post_id,
                    "user_sub": user_sub,
                    "created_at": now,
                    # Proyeccion para "posts que gustaron a un usuario".
                    "GSI2PK": f"USER#{user_sub}",
                    "GSI2SK": f"LIKE#{now}#{post_id}",
                },
                ConditionExpression="attribute_not_exists(PK)",
            )
            table.update_item(
                Key={"PK": f"POST#{post_id}", "SK": "META"},
                UpdateExpression="ADD like_count :one",
                ExpressionAttributeValues={":one": 1},
            )
        except ClientError as e:
            if e.response["Error"]["Code"] != "ConditionalCheckFailedException":
                raise
            # Ya tenia like de este usuario: no se duplica el contador,
            # se responde igual como "liked=true".
        return ok({"postId": post_id, "liked": True})

    return err(405, "Metodo no soportado")
