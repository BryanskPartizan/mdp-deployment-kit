# Прикладные заглушки

Каталог содержит минимальные сервисы для проверки полного прикладного контура deployment-kit:

- `api` — создаёт, читает и обновляет карточки лидов, хранит их в Redis при наличии `REDIS_URL`;
- `gateway` — проксирует маршруты `/leads`, `/entities` и `/test-runs` в API;
- `frontend` — отдаёт CRM-доску лидов, таблицу лидов, форму редактирования и вкладку с результатами тестов.

Сервисы намеренно написаны на Node.js без внешних npm-зависимостей. Это снижает размер цепочки поставки и упрощает сборку demo-образов.

Основные маршруты:

```text
GET  /health
GET  /leads
POST /leads
GET  /leads/:id
PATCH /leads/:id
GET  /entities
POST /entities
GET  /entities/:id
PATCH /entities/:id
GET  /test-runs
POST /test-runs
GET  /test-runs/:id
```

Маршруты `/entities` оставлены как совместимость для старых проверок, но новая модель данных — карточка лида:

```json
{
  "name": "Иван Петров",
  "company": "Example LLC",
  "email": "lead@example.com",
  "phone": "+7...",
  "source": "website",
  "status": "new",
  "owner": "manager",
  "budget": 50000,
  "notes": "Контекст сделки"
}
```

Конфигурация читается из переменных окружения и из Vault Agent файла `/vault/secrets/config` в формате `KEY=value`.
