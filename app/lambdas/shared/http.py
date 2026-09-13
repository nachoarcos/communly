import json
import decimal


def _default(value):
    # DynamoDB devuelve numeros como Decimal; json no sabe serializarlos.
    if isinstance(value, decimal.Decimal):
        return int(value) if value % 1 == 0 else float(value)
    raise TypeError(f"Object of type {type(value)} is not JSON serializable")


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=_default),
    }


def ok(body, status_code=200):
    return _response(status_code, body)


def err(status_code, message):
    return _response(status_code, {"error": message})
