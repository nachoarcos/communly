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
    groups = raw if isinstance(raw, list) else str(raw).split(",")
    return "admins" in groups
