import os
import logging
from datetime import datetime, timezone
import boto3
from botocore.exceptions import ClientError
from boto3.dynamodb.types import TypeDeserializer
from shared.dynamo import table

ses = boto3.client("ses")
FROM_ADDRESS = os.environ.get("SES_FROM_ADDRESS")
MOCK_MODE = os.environ.get("SES_MOCK_MODE", "false").lower() == "true"
_deserializer = TypeDeserializer()
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _deserialize_image(image):
    return {k: _deserializer.deserialize(v) for k, v in image.items()}


def handler(event, context):
    # El event_source_mapping ya filtra por SK begins_with COMMENT#
    # (ver modules/stream-consumers/notifications.tf).
    for record in event.get("Records", []):
        image = _deserialize_image(record["dynamodb"]["NewImage"])
        post_id = image.get("post_id")
        comment_id = image.get("comment_id")
        comment_author_sub = image.get("author_sub")
        if not post_id:
            continue

        post = table.get_item(Key={"PK": f"POST#{post_id}", "SK": "META"}).get("Item")
        if not post or post.get("author_sub") == comment_author_sub:
            # Sin post, o el autor comenta su propio post: nadie a
            # quien notificar.
            continue

        author_sub = post["author_sub"]
        now = datetime.now(timezone.utc).isoformat()

        # Registro de notificacion en la propia tabla (visible en
        # /me/notifications).
        table.put_item(
            Item={
                "PK": f"USER#{author_sub}",
                "SK": f"NOTIFICATION#{now}#{comment_id}",
                "type": "new_comment",
                "post_id": post_id,
                "comment_id": comment_id,
                "read_at": None,
            }
        )

        # Email: requiere que el email del destinatario este
        # denormalizado en su propio item de perfil
        # (PK=USER#<sub>/PROFILE, atributo "email"), sincronizado desde
        # Cognito al confirmar el registro (Post Confirmation trigger).
        # Cognito sigue siendo la fuente de verdad de la autenticacion,
        # pero no conviene llamar a AdminGetUser en cada comentario solo
        # para leer un email que cambia con poca frecuencia.
        profile = table.get_item(Key={"PK": f"USER#{author_sub}", "SK": "PROFILE"}).get("Item")
        recipient_email = profile.get("email") if profile else None
        if not recipient_email:
            continue

        # Email: mejor esfuerzo, no critico. Si SES_MOCK_MODE esta
        # activo (entornos donde SES no esta concedido, p.ej. el
        # laboratorio de dev), NO SE INTENTA la llamada real en
        # absoluto -- se deja constancia en el log de que se habria
        # enviado, y se sigue. Si el mock esta desactivado pero la
        # llamada real falla igualmente (permiso, sandbox, destinatario
        # sin verificar...), el try/except evita que un fallo puramente
        # accesorio tumbe el registro de la notificacion, que ya se ha
        # guardado un par de lineas antes.
        if MOCK_MODE:
            logger.info(
                "MOCK SES_MOCK_MODE=true: se habria enviado email a %s (post_id=%s, comment_id=%s)",
                recipient_email,
                post_id,
                comment_id,
            )
        else:
            try:
                ses.send_email(
                    Source=FROM_ADDRESS,
                    Destination={"ToAddresses": [recipient_email]},
                    Message={
                        "Subject": {"Data": "Nuevo comentario en tu post de Communly"},
                        "Body": {
                            "Text": {
                                "Data": "Alguien ha comentado tu post. Entra en Communly para verlo."
                            }
                        },
                    },
                )
            except ClientError as e:
                logger.warning(
                    "No se pudo enviar el email de notificacion (post_id=%s, comment_id=%s): %s",
                    post_id,
                    comment_id,
                    e,
                )
