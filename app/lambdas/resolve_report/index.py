from datetime import datetime, timezone
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import is_admin


def handler(event, context):
    if not is_admin(event):
        return err(403, "Requiere rol de administrador")

    report_id = (event.get("pathParameters") or {}).get("reportId")
    if not report_id:
        return err(400, "reportId requerido")

    try:
        body = event.get("body")
        import json

        parsed = json.loads(body) if body else {}
    except Exception:
        parsed = {}

    post_id = parsed.get("postId")
    if not post_id:
        return err(400, "postId requerido en el body")

    now = datetime.now(timezone.utc).isoformat()

    # Al eliminar GSI2PK/GSI2SK (no basta con vaciarlos), el item
    # desaparece del indice sparse MODERATION#OPEN sin borrar el
    # registro historico de la denuncia en la tabla base.
    table.update_item(
        Key={"PK": f"POST#{post_id}", "SK": f"REPORT#{report_id}"},
        UpdateExpression="SET resolved_at = :now REMOVE GSI2PK, GSI2SK",
        ExpressionAttributeValues={":now": now},
    )

    return ok({"reportId": report_id, "postId": post_id, "resolvedAt": now})
