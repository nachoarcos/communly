# DynamoDB Access Patterns

## Tabla

```text
PK / SK
GSI1PK / GSI1SK
GSI2PK / GSI2SK
ttl
```

## GSI1

### Feed global shardeado y sparse

```text
GSI1PK = POSTS#<shard>
GSI1SK = PUBLISHED#<publishedAt>#<postId>
```

Solo los posts `PUBLISHED` contienen estas claves.

### Followers

```text
GSI1PK = USER#<followedSub>
GSI1SK = FOLLOWER#<createdAt>#<followerSub>
```

## GSI2

```text
USER#<sub> / POST#...
USER#<sub> / COMMENT#...
USER#<sub> / LIKE#POST#...
USER#<sub> / LIKE#COMMENT#...
TAG#<slug> / POST#...
MODERATION#OPEN / <createdAt>#POST#...#REPORT#...
```

## Patrones

| Necesidad | Operación | Índice |
|---|---|---|
| Usuario por ID | GetItem | Base |
| Usuario por username | GetItem | Base |
| Post por ID | GetItem | Base |
| Últimos posts | Query por shard + merge | GSI1 |
| Posts usuario | Query | GSI2 |
| Comentarios post | Query | Base |
| Comentarios usuario | Query | GSI2 |
| Likes post | Query/GetItem | Base |
| Likes usuario | Query | GSI2 |
| Tags post | Query | Base |
| Posts por tag | Query | GSI2 |
| Following | Query | Base |
| Followers | Query | GSI1 |
| Feed personalizado | Query | Base |
| Notificaciones | Query | Base |
| Moderación abierta | Query | GSI2 |
