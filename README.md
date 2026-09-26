# test

Песочница для проверки Claude Code Cloud Sessions.

## Как запустить

```bash
pip install -e ".[dev]"          # установка
uvicorn app.main:app --reload    # запуск сервиса
curl localhost:8000/health       # проверка
pytest -q                        # тесты
```

## Эндпоинты

| Метод и путь | Параметры | Ответ |
|---|---|---|
| `GET /` | — | `{"message": "hello"}` |
| `GET /health` | — | `{"status": "ok"}` |
| `GET /commission` | `price` (> 0), `percent` (0 < x ≤ 20, по умолчанию 3), `min_commission` (≥ 0, по умолчанию 50000) | `{"commission", "percent", "price"}` |

Комиссия = `price × percent / 100`, но не меньше `min_commission`. При некорректных параметрах — HTTP 422.

Пример:

```bash
curl "localhost:8000/commission?price=5000000"
# {"commission":150000.0,"percent":3.0,"price":5000000.0}
```
