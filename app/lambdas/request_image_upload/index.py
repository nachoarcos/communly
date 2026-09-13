import os
import json
import uuid
import boto3
from shared.http import ok, err
from shared.auth import get_user_sub

s3 = boto3.client("s3")
BUCKET = os.environ.get("IMAGES_BUCKET")
UPLOAD_URL_TTL_SECONDS = 300


def handler(event, context):
    user_sub = get_user_sub(event)
    if not user_sub:
        return err(401, "No autenticado")

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return err(400, "JSON invalido")

    content_type = body.get("contentType", "")
    if not content_type.startswith("image/"):
        return err(400, "contentType debe ser image/*")

    image_id = str(uuid.uuid4())
    extension = content_type.split("/")[-1] or "bin"
    # Bajo el usuario, no bajo un post: al escribir un post NUEVO todavia
    # no existe ningun post_id al que asociar la imagen. La asociacion
    # real queda implicita en el propio markdown (la URL de la imagen
    # se inserta en el cuerpo del post/comentario), no en una tabla.
    key = f"images/{user_sub}/{image_id}.{extension}"

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
            # (ver modules/storage/cloudfront.tf, comportamiento
            # /images/*). Al ser relativa y servirse la SPA desde el
            # mismo dominio de CloudFront, funciona tal cual dentro del
            # markdown sin anadir el dominio a mano.
            "publicPath": f"/{key}",
            "expiresInSeconds": UPLOAD_URL_TTL_SECONDS,
        }
    )
