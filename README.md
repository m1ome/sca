# SCA — SaaS-бэкенд

Strong Customer Authentication как сервис: мерчанты подключаются по API, их
пользователи подтверждают действия (платежи, логины) криптографической подписью
на привязанном устройстве. Прототип логики — в соседнем репозитории
`../sca-proto` (Go), мобильный клиент — `../sca-client` (Flutter).

Это umbrella-проект на Elixir/Phoenix: домен отдельно, три HTTP-входа отдельно.

## Структура

| Приложение | Что это | Порт (dev) |
|---|---|---|
| `apps/sca` | Бизнес-логика: `Sca.Repo`, контексты, Oban-воркеры, фабрики для тестов | — |
| `apps/sca_api` | JSON API для внешних мерчантов (без HTML и ассетов) | 4001 |
| `apps/sca_web` | Веб-кабинет мерчанта (LiveView) | 4000 |
| `apps/sca_admin` | Внутренняя админка (LiveView, Oban Web) | 4002 |

Доступ к базе есть только у `apps/sca` — веб-приложения ходят в домен через
его публичное API, а не в `Repo` напрямую.

## Запуск

```bash
docker compose up -d db     # Postgres 18 на localhost:55433
mix setup                   # deps, ассеты, ecto.create + migrate
mix phx.server              # поднимает все три эндпоинта разом
```

- кабинет мерчанта — <http://localhost:4000>
- API — <http://localhost:4001>
- админка — <http://localhost:4002>, очереди Oban — <http://localhost:4002/dev/oban>,
  LiveDashboard — <http://localhost:4002/dev/dashboard>

Порт 55433, а не 5432, чтобы не конфликтовать ни с системным Postgres, ни с
базой `sca-proto` (55432). В проде всё берётся из `DATABASE_URL`,
`SECRET_KEY_BASE` и `WEB_PORT` / `API_PORT` / `ADMIN_PORT` (`config/runtime.exs`).

## Разработка

```bash
mix test          # тесты всех приложений
mix lint          # format --check-formatted + credo --strict
mix precommit     # компиляция без варнингов, format, credo, тесты
```

Тестовая база — `sca_test` на том же контейнере, песочница Ecto. Фабрики —
`Sca.Factory` (ExMachina). Джобы в тестах не выполняются (`Oban` в режиме
`testing: :manual`), проверяются через `Oban.Testing`.

## Идентификаторы

Первичный ключ везде — UUID (`binary_id`). Рядом с ним у сущностей есть
человеко-читаемый `public_id`: `TN-1` у тенанта, `CON-42` у коннекта. Его
генерирует Postgres из отдельной последовательности на каждую таблицу, поэтому
параллельные вставки не конфликтуют.

```elixir
# миграция
create table(:tenants, primary_key: false) do
  add :id, :binary_id, primary_key: true
  timestamps(type: :utc_datetime_usec)
end

Sca.Repo.Migration.add_public_id(:tenants, "TN")

# схема
defmodule Sca.Tenants.Tenant do
  use Sca.Schema, public_id: "TN"

  schema "tenants" do
    public_id_field()
    timestamps()
  end
end
```

Разбор и проверка приходящего от пользователя идентификатора — `Sca.PublicId`
(`parse/1`, `belongs_to?/2`).

## Что дальше

Доменные сущности (тенанты, коннекты, авторизации), проверка подписей ECDSA
P-256, пуши, аутентификация мерчанта и админа, Dockerfile и CI.
