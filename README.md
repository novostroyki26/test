# test

Песочница для проверки Claude Code Cloud Sessions.

## Как запустить

```bash
pip install -e ".[dev]"          # установка
uvicorn app.main:app --reload    # запуск сервиса
curl localhost:8000/health       # проверка
pytest -q                        # тесты
```
