import json
import uuid
from datetime import datetime, timezone
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub


def handler(event, context):
    reporter_sub = get_user_sub(event)
    if not reporter_sub:
        return err(401, "No autenticado")

    post_id = (event.get("pathParameters") or {}).get("postId")
    if not post_id:
        return err(400, "postId requerido")

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return err(400, "JSON invalido")

    reason = body.get("reason", "")
    report_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    table.put_item(
        Item={
            "PK": f"POST#{post_id}",
            "SK": f"REPORT#{report_id}",
            "report_id": report_id,
            "post_id": post_id,
            "reporter_sub": reporter_sub,
            "reason": reason,
            "created_at": now,
            # Sparse: solo las denuncias abiertas viven en este indice.
            # Se elimina al resolver (ver resolve_report/index.py).
            "GSI2PK": "MODERATION#OPEN",
            "GSI2SK": f"{now}#POST#{post_id}#REPORT#{report_id}",
        }
    )

    return ok({"reportId": report_id, "postId": post_id}, 201)
