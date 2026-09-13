import os
import re
import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)

USERNAME_RE = re.compile(r"^[a-z0-9_]{3,30}$")


def handler(event, context):
    attrs = event["request"]["userAttributes"]
    username = attrs.get("custom:username", "")

    # El Hosted UI CLASICO de Cognito no permite recoger atributos
    # custom en el formulario de registro (solo email/contrasena) --
    # asi que la inmensa mayoria de altas llegan aqui SIN username, no
    # como una excepcion rara. Bloquear el registro en ese caso rompe
    # el alta por completo para todo el mundo. En vez de eso, se deja
    # pasar sin username: post_confirmation creara el perfil con
    # needs_username=True, y el frontend ya sabe llevar a esos usuarios
    # a /settings para elegir uno (ver app/frontend/src/pages/Callback.jsx).
    if not username:
        return event

    # Si SI llega un username (via un formulario propio futuro, o
    # llamando a la API de Cognito directamente en vez del Hosted UI),
    # aqui se valida formato y unicidad best-effort como antes.
    if not USERNAME_RE.match(username):
        raise Exception("El nombre de usuario debe tener 3-30 caracteres (a-z, 0-9, _)")

    # Comprobacion best-effort, NO es la garantia final de unicidad.
    # Da feedback inmediato en el caso comun (username ya tomado) sin
    # esperar a que el usuario termine de verificar su email. La
    # garantia real es la condicion de escritura transaccional en el
    # trigger post_confirmation.
    existing = table.get_item(Key={"PK": f"USERNAME#{username}", "SK": "PROFILE"}).get("Item")
    if existing:
        raise Exception("Ese nombre de usuario ya esta en uso")

    return event
