import os
from datetime import datetime, timezone
import boto3
from boto3.dynamodb.types import TypeDeserializer
from shared.dynamo import table

ses = boto3.client("ses")
FROM_ADDRESS = os.environ.get("SES_FROM_ADDRESS")
_deserializer = TypeDeserializer()


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

        ses.send_email(
            Source=FROM_ADDRESS,
            Destination={"ToAddresses": [recipient_email]},
            Message={
                "Subject": {"Data": "Nuevo comentario en tu post de Communly"},
                "Body": {"Text": {"Data": "Alguien ha comentado tu post. Entra en Communly para verlo."}},
            },
        )
