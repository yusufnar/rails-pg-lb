# Rails Database Load Balancer

A Ruby on Rails application demonstrating advanced database load balancing techniques with **PostgreSQL** read replicas, **Redis**-based health tracking, and a custom **application-layer** routing strategy.

## 🚀 Key Features

| Feature | Details |
| :--- | :--- |
| **Read/Write Splitting** | Writes go to Primary; reads are distributed across healthy replicas. |
| **Health-Aware Routing** | Replicas are automatically excluded when they lag >1s, lose connectivity, or become zombies. |
| **Circuit Breaker** | If Redis is unavailable, the load balancer backs off for 10s and falls back to all replicas. |
| **Local Caching** | Healthy replica list is cached for 2s to minimize Redis round-trips on every request. |
| **Zombie Detection** | A replica is marked unhealthy if `last_msg_receipt_lag_s > 20s` on a streaming connection. |
| **Infrastructure as Code** | Fully Dockerized: Primary, 2 Replicas, Redis, Rails app, and a Health Check sidecar. |

## 🛠 Tech Stack

| Layer | Technology |
| :--- | :--- |
| Framework | Ruby on Rails 8.1.2 |
| Database | PostgreSQL 17 — 1 Primary + 2 Streaming Replicas |
| State / Cache | Redis 7 |
| Containerization | Docker & Docker Compose |

## 🏗 Architecture

The system implements a **Read/Write Split** at the application layer:

- **Writes** (`POST`, `PUT`, `PATCH`, `DELETE`) → Primary
- **Reads** (`GET`, `HEAD`) → `DatabaseLoadBalancer` → healthy replica (round-robin), with Primary as fallback

```text
                          ┌──────────────────────┐
                          │    User Request      │
                          └──────────┬───────────┘
                                     │
                          ┌──────────▼────────────┐
                          │ ApplicationController │
                          │   (around_action)     │
                          └────┬────────────┬─────┘
                               │            │
                          Write Ops     Read Ops
                          (POST/PUT     (GET/HEAD)
                           DELETE)          │
                               │    ┌───────▼─────────┐
                               │    │  Database       │◄── Round Robin
                               │    │  LoadBalancer   │    Selection
                               │    └──┬─────────┬────┘
                               │       │         │
                     ┌─────────▼───┐   │         │
                     │   Primary   │   │         │
                     │   (Write)   │◄──┘         │    Fallback: No healthy
                     │             │  Fallback   │    replicas → Primary
                     └──────┬──────┘             │
                            │                    │
                      Async │ WAL          ┌─────▼─────┐
                  Streaming │ Replication  │           │
                            │          ┌───▼───┐ ┌─────▼─┐
                            ├─────────►│Rep. 1 │ │Rep. 2 │
                            │          └───┬───┘ └───┬───┘
                            │              │         │
                  ┌─────────┴──────────────┴─────────┘
                  │
         ┌────────▼─────────┐       ┌──────────┐
         │  Health Check    │──────►│  Redis   │
         │  Service (1s)    │       │  (State) │
         └──────────────────┘       └────┬─────┘
                                         │
                              LoadBalancer reads
                              health status from
                              Redis (with Circuit
                              Breaker protection)
```

### 1. Database Topology

| Node | Role | Notes |
| :--- | :--- | :--- |
| `postgres-primary` | Write | Fallback for reads when no replicas are healthy |
| `postgres-replica1` | Read | Async streaming replica |
| `postgres-replica2` | Read | Async streaming replica |

### 2. Health Check Service

`bin/health_check.rb` runs as a standalone daemon (container: `rds_health_check`) and polls every **1 second**:

- Connects to each node with a 2s timeout
- On **replicas**: queries `pg_stat_wal_receiver` + `pg_last_xact_replay_timestamp()` to compute lag
- Marks a replica **unhealthy** if any of the following is true:
  - WAL replay is explicitly paused (`pg_is_wal_replay_paused()`)
  - Replication lag exceeds **1s**
  - `last_msg_receipt_lag_s > 20s` on a streaming connection (zombie detection)
- Writes the pruned status JSON to Redis keys: `db_status:replica_1`, `db_status:replica_2`

### 3. Load Balancing Logic

`app/services/database_load_balancer.rb` is a thread-safe Singleton that selects a read role on every request:

1. **Local Cache** — if last Redis check was <2s ago, return cached result immediately
2. **Circuit Breaker** — if Redis failed recently (<10s ago), skip Redis and use all replicas
3. **Redis Fetch** — read `db_status:replica_*` keys and collect healthy roles
4. **Round-Robin** — rotate through healthy replicas
5. **Primary Fallback** — if no healthy replicas exist, return `:writing` (Primary)

### 4. Request Lifecycle

```ruby
around_action :switch_database

def switch_database(&block)
  if request.get? || request.head?
    role = DatabaseLoadBalancer.instance.reading_role
    ApplicationRecord.connected_to(role: role) { yield }
  else
    yield  # writes always go to Primary
  end
end
```

## 🏁 Getting Started

### Prerequisites

- Docker & Docker Compose

### Setup

1. **Start all services:**
   ```bash
   docker-compose up --build
   ```

2. **Initialize the database:**
   ```bash
   docker-compose run web rails db:prepare
   ```

3. **Open the app:**
   Visit [http://localhost:3000](http://localhost:3000) — the page shows the active DB role, node IP, and current replication lag.

## 🧪 Testing Scenarios

Scripts to simulate various failure modes and verify load balancer behavior:

| Script | Scenario |
| :--- | :--- |
| `test_replica1_down.sh` | Stops `postgres-replica1`; verifies traffic shifts to `replica2`. |
| `test_replica1_lag.sh` | Pauses WAL replay on `replica1` to simulate lag >1s. |
| `test_both_replicas_down.sh` | Stops both replicas; verifies read fallback to Primary. |
| `test_both_replicas_lag.sh` | Pauses WAL replay on both replicas simultaneously. |
| `test_redis_down.sh` | Stops Redis to exercise the Circuit Breaker. |
| `test_primary_down.sh` | Stops Primary; reads continue via replicas, writes fail. |
| `test_network_partition.sh` | Blocks traffic between Primary and Replicas via `iptables`. |
| `test_staggered_recovery.sh` | Stops both replicas, then restores them one at a time. |
| `generate_traffic.sh` | Sends concurrent requests to observe load distribution. |
| `run_all_tests.sh` | Runs all test scripts sequentially. Usage: `./run_all_tests.sh <duration>` |

## 📊 Monitoring

| Script | Description |
| :--- | :--- |
| `monitor_lb.sh` | Polls the load balancer status endpoint every 1s with color-coded output. |
| `monitor_replica_lag.sh` | Queries `pg_stat_wal_receiver` on each replica and prints lag metrics in tabular form. |
| `monitor_redis_routing.sh` | Tracks Redis routing decisions and response times in real time. |

## 📂 Project Structure

```
.
├── app/
│   ├── controllers/application_controller.rb   # around_action: read/write routing
│   └── services/database_load_balancer.rb      # Singleton load balancer (cache + circuit breaker)
├── bin/
│   └── health_check.rb                         # Standalone health monitoring daemon
├── config/
│   └── database.yml                            # Multi-DB config (primary + 2 replicas)
├── docker/
│   └── postgres/                               # PostgreSQL init & replication scripts
├── docker-compose.yml                          # Full infrastructure definition
├── monitor_lb.sh                               # Load balancer live monitor
├── monitor_replica_lag.sh                      # Replication lag live monitor
├── monitor_redis_routing.sh                    # Redis routing live monitor
├── run_all_tests.sh                            # Master test runner
└── test_*.sh                                   # Individual failure scenario scripts
```
