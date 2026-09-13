import os
import boto3

TABLE_NAME = os.environ.get("TABLE_NAME")

_dynamodb = boto3.resource("dynamodb")
table = _dynamodb.Table(TABLE_NAME) if TABLE_NAME else None
