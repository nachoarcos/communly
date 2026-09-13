import os
import re
import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)

USERNAME_RE = re.compile(r"^[a-z0-9_]{3,30}$")


def handler(event, context):
    attrs = event["request"]["userAttributes"]
    username = attrs.get("custom:username", "")

    # required=false es obligatorio para atributos custom en Cognito
    # (ver modules/cognito/user_pool.tf); la obligatoriedad real se
    # impone aqui, lanzando una excepcion bloquea el registro.
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
