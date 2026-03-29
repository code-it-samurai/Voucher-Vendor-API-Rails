# Observability

The project ships with built-in observability tools, all accessible from your browser once the containers are running.

## Dashboards

| Tool | URL | Purpose |
|---|---|---|
| **Dozzle** | [localhost:8080](http://localhost:8080) | Real-time container log viewer — stream logs from all services in one place |
| **Sidekiq Dashboard** | [localhost:3000/sidekiq](http://localhost:3000/sidekiq) | Monitor background job queues, retries, failures, and processing stats |

## Dozzle — Container Logs

[Dozzle](http://localhost:8080) gives you a real-time, browser-based view of all container logs. No setup needed — it's included in the Docker Compose stack.

- View logs from `web`, `sidekiq`, `postgres`, and `redis` containers in one place
- Filter by container or search across all logs
- Color-coded log levels for quick scanning

## Sidekiq Dashboard

The [Sidekiq Dashboard](http://localhost:3000/sidekiq) is mounted at `/sidekiq` on the Rails server. It shows:

- **Processed / Failed** job counts
- **Retry queue** with failure details and next retry time
- **Scheduled jobs** waiting to execute
- **Live polling** of active workers

## CLI Log Commands

```bash
# Tail logs from all containers
docker compose logs -f

# View only the web service logs
docker compose logs -f web

# View only Sidekiq worker logs
docker compose logs -f sidekiq

# View last 100 lines from web
docker compose logs --tail=100 web
```

## Rails Application Logs

Inside the container, Rails logs are written to `STDOUT` in development. Key things to look for:

- **Request logs** — method, path, status, duration
- **SQL queries** — every query is logged with timing
- **Sidekiq job logs** — enqueue, start, complete, and failure events
- **Idempotency hits** — when a duplicate `reference_code` is detected
