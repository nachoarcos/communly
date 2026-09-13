import os
import time
from boto3.dynamodb.conditions import Key
from boto3.dynamodb.types import TypeDeserializer
from shared.dynamo import table

FEED_ITEM_TTL_S = int(os.environ.get("FEED_ITEM_TTL_S", str(60 * 60 * 24 * 90)))
_deserializer = TypeDeserializer()


def _deserialize_image(image):
    return {k: _deserializer.deserialize(v) for k, v in image.items()}


def handler(event, context):
    # El event_source_mapping ya filtra por INSERT/MODIFY con
    # status = published (ver modules/stream-consumers/fan_out.tf); este
    # handler no necesita repetir ese filtro, solo procesar cada registro.
    for record in event.get("Records", []):
        image = _deserialize_image(record["dynamodb"]["NewImage"])
        post_id = image.get("post_id")
        author_sub = image.get("author_sub")
        published_at = image.get("published_at")
        title = image.get("title")
        if not (post_id and author_sub and published_at):
            continue

        # 1. Obtener todos los seguidores del autor (GSI1).
        followers = []
        last_key = None
        while True:
            kwargs = {
                "IndexName": "GSI1",
                "KeyConditionExpression": Key("GSI1PK").eq(f"USER#{author_sub}")
                & Key("GSI1SK").begins_with("FOLLOWER#"),
            }
            if last_key:
                kwargs["ExclusiveStartKey"] = last_key
            res = table.query(**kwargs)
            followers.extend(res.get("Items", []))
            last_key = res.get("LastEvaluatedKey")
            if not last_key:
                break

        if not followers:
            continue

        # 2. Escribir un item FEED por seguidor. put_item con la misma
        #    clave (SK=FEED#<ts>#<post_id>) es idempotente: si este
        #    registro del stream se reprocesa tras un fallo parcial, se
        #    sobrescribe sin duplicar.
        with table.batch_writer() as batch:
            for follower in followers:
                batch.put_item(
                    Item={
                        "PK": follower["PK"],  # USER#<follower_sub>
                        "SK": f"FEED#{published_at}#{post_id}",
                        "post_id": post_id,
                        "author_sub": author_sub,
                        "post_title": title,
                        "published_at": published_at,
                        "ttl": int(time.time()) + FEED_ITEM_TTL_S,
                    }
                )
