# El JWT Authorizer nativo de API Gateway ya ha validado firma y
# expiracion antes de invocar el handler. cognito:groups NO se evalua
# en el Authorizer (una HTTP API v2 solo evalua scopes OAuth, no grupos
# nativos de Cognito): las rutas admin_only dependen de is_admin() aqui.


def get_claims(event):
    return (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
    ) or {}


def get_user_sub(event):
    return get_claims(event).get("sub")


def is_admin(event):
    raw = get_claims(event).get("cognito:groups")
    if not raw:
        return False

    if isinstance(raw, list):
        groups = raw
    else:
        # El JWT Authorizer de API Gateway (HTTP API) convierte los
        # claims que son arrays JSON en el token original (como
        # cognito:groups) a un string CON CORCHETES, p.ej. "[admins]"
        # o "[admins, editors]" -- no a una lista limpia separada por
        # comas. Hay que quitar los corchetes (y espacios sueltos)
        # antes de separar. Sin esto, "admins" in groups siempre da
        # False aunque el usuario si pertenezca al grupo (los
        # corchetes nunca coinciden con nada).
        cleaned = str(raw).strip("[]")
        groups = [g.strip() for g in cleaned.split(",") if g.strip()]

    return "admins" in groups
