import os
import json
import uuid
import boto3
from datetime import datetime, timezone
from shared.dynamo import table
from shared.http import ok, err
from shared.auth import get_user_sub

s3 = boto3.client("s3")
BUCKET = os.environ.get("IMAGES_BUCKET")
UPLOAD_URL_TTL_SECONDS = 300


def handler(event, context):
    user_sub = get_user_sub(event)
    if not user_sub:
        return err(401, "No autenticado")

    post_id = (event.get("pathParameters") or {}).get("postId")
    if not post_id:
        return err(400, "postId requerido")

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return err(400, "JSON invalido")

    content_type = body.get("contentType", "")
    if not content_type.startswith("image/"):
        return err(400, "contentType debe ser image/*")

    image_id = str(uuid.uuid4())
    extension = content_type.split("/")[-1] or "bin"
    key = f"images/{post_id}/{image_id}.{extension}"
    now = datetime.now(timezone.utc).isoformat()

    # Registrar la imagen en la tabla ANTES de firmar la URL: si el
    # usuario nunca completa la subida, queda un registro huerfano
    # detectable (sin objeto real en S3), preferible a un objeto en S3
    # sin registro en la tabla.
    table.put_item(
        Item={
            "PK": f"POST#{post_id}",
            "SK": f"IMAGE#{image_id}",
            "image_id": image_id,
            "post_id": post_id,
            "uploaded_by_sub": user_sub,
            "s3_key": key,
            "created_at": now,
        }
    )

    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": BUCKET, "Key": key, "ContentType": content_type},
        ExpiresIn=UPLOAD_URL_TTL_SECONDS,
    )

    return ok(
        {
            "imageId": image_id,
            "uploadUrl": upload_url,
            # Ruta publica final una vez CloudFront sirva el objeto
            # (ver modules/storage/cloudfront.tf, comportamiento /images/*).
            "publicPath": f"/{key}",
            "expiresInSeconds": UPLOAD_URL_TTL_SECONDS,
        }
    )
