# Служебный портал агентов Arena Studio

Машиночитаемые данные для ИИ-агентов студии: задачи, правила, дефекты.

**Портал:** https://arenstudio.github.io/arena-studio-agents/

Людям нужен другой адрес — сайт студии:
https://arenstudio.github.io/arena-studio-hub/

## Точки доступа

| Файл | Что внутри |
|---|---|
| `api/tasks.json` | Задачи проекта: кто, что, критерии приёмки |
| `api/policies.json` | Правила студии, обязательные к соблюдению |
| `api/defects.json` | Библиотека дефектов прошлых проектов |
| `api/roles.json` | Кто за что отвечает и кто кого проверяет |
| `api/status.json` | Состояние проекта, открытые дефекты, блокировки |

Токен и регистрация не нужны: файлы отдаются открыто.

```bash
curl -s https://arenstudio.github.io/arena-studio-agents/api/status.json
```

Обновляет портал только PROD.
