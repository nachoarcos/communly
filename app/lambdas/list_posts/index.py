import os
import json
import base64
from boto3.dynamodb.conditions import Key
from shared.dynamo import table
from shared.http import ok

SHARD_COUNT = int(os.environ.get("FEED_SHARD_COUNT", "5"))
DEFAULT_LIMIT = 20
MAX_LIMIT = 50


# Cursor: { "<shard>": {"key": <ExclusiveStartKey> | None, "done": bool} }
# Un shard "done" ya no se vuelve a consultar. Un shard sin entrada se
# consulta desde el principio.
def decode_cursor(raw):
    if not raw:
        return {}
    try:
        return json.loads(base64.urlsafe_b64decode(raw.encode()).decode())
    except Exception:
        return {}


def encode_cursor(cursor):
    return base64.urlsafe_b64encode(json.dumps(cursor).encode()).decode()


def handler(event, context):
    qs = event.get("queryStringParameters") or {}
    limit = min(int(qs.get("limit", DEFAULT_LIMIT)), MAX_LIMIT)
    cursor = decode_cursor(qs.get("cursor"))

    # 1. Consulta cada shard no agotado. Se pide `limit` items por
    #    shard: sobre-pedir es intencional, en el peor caso todos los
    #    items de la pagina final vienen de un unico shard.
    results = []
    for shard in range(SHARD_COUNT):
        state = cursor.get(str(shard))
        if state and state.get("done"):
            continue

        kwargs = {
            "IndexName": "GSI1",
            "KeyConditionExpression": Key("GSI1PK").eq(f"POSTS#{shard}"),
            "ScanIndexForward": False,  # mas reciente primero
            "Limit": limit,
        }
        if state and state.get("key"):
            kwargs["ExclusiveStartKey"] = state["key"]

        res = table.query(**kwargs)
        items = res.get("Items", [])
        for item in items:
            item["__shard"] = shard
        results.append({"shard": shard, "items": items, "exhausted": len(items) < limit})

    # 2. Fusiona todos los items y ordena por fecha de publicacion
    #    descendente (el prefijo PUBLISHED# es fijo; el orden
    #    lexicografico del timestamp ISO ya es orden cronologico).
    merged = [item for r in results for item in r["items"]]
    merged.sort(key=lambda i: i["GSI1SK"], reverse=True)
    page = merged[:limit]

    # 3. Cursor de la siguiente pagina: para cada shard, avanza solo
    #    hasta el ultimo item de ESE shard que realmente se devolvio en
    #    esta pagina (no hasta el final del lote sobre-pedido), para no
    #    saltarse items que quedaron fuera por el corte del merge.
    next_cursor = dict(cursor)
    for r in results:
        shard_items_in_page = [i for i in page if i["__shard"] == r["shard"]]
        if shard_items_in_page:
            last = shard_items_in_page[-1]
            next_cursor[str(r["shard"])] = {
                # DynamoDB exige que el ExclusiveStartKey de una Query
                # sobre un GSI incluya TANTO la clave de la tabla base
                # (PK/SK) COMO la clave del propio indice (GSI1PK/
                # GSI1SK). Guardar solo PK/SK produce una
                # ValidationException en la siguiente pagina (se ve
                # como un 500 sin mas detalle en el cliente).
                "key": {
                    "PK": last["PK"],
                    "SK": last["SK"],
                    "GSI1PK": last["GSI1PK"],
                    "GSI1SK": last["GSI1SK"],
                },
                "done": False,
            }
        elif r["exhausted"]:
            next_cursor[str(r["shard"])] = {"done": True}
        # Si el shard no aporto items a la pagina pero tampoco esta
        # agotado, se deja el cursor tal cual: se reconsultara desde el
        # mismo punto en la siguiente llamada.

    all_done = all(s.get("done") for s in next_cursor.values()) and len(next_cursor) == SHARD_COUNT

    clean_page = [
        {k: v for k, v in i.items() if k not in ("PK", "SK", "GSI1PK", "GSI1SK", "__shard")}
        for i in page
    ]

    return ok({"items": clean_page, "nextCursor": None if all_done else encode_cursor(next_cursor)})
