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
| `GET /version` | — | `{"version": "0.1.0"}` |
| `GET /mortgage` | `price` (> 0), `down` (≥ 0, < price), `rate` (0–50, % годовых), `years` (> 0) | `{"monthly_payment", "overpayment"}` |
| `GET /commission` | `price` (> 0), `percent` (0 < x ≤ 20, по умолчанию 3), `min_commission` (≥ 0, по умолчанию 50000) | `{"commission", "percent", "price"}` |

Комиссия = `price × percent / 100`, но не меньше `min_commission`. При некорректных параметрах — HTTP 422.

Пример:

```bash
curl "localhost:8000/commission?price=5000000"
# {"commission":150000.0,"percent":3.0,"price":5000000.0}
```
