# Rails Database Load Balancer

A Ruby on Rails application demonstrating advanced database load balancing techniques with **PostgreSQL** read replicas, **Redis**-based health tracking, and custom **Application Layer** routing logic.

## 🚀 Key Features

*   **Custom Load Balancer**: Implemented in Ruby (`DatabaseLoadBalancer` service), handling intelligent read/write splitting.
*   **Health Aware Routing**: Automatically routes traffic away from unhealthy or lagging replicas.
*   **Circuit Breaker Pattern**: Protects the application from Redis failures by temporarily backing off and defaulting to safe routing.
*   **Replica Lag Detection**: Monitors replication lag and pauses routing to replicas exceeding the threshold (1s).
*   **Infrastructure as Code**: Fully dockerized setup with Primary, 2 Replicas, Redis, and a dedicated Health Check service.

## 🛠 Tech Stack

*   **Framework**: Ruby on Rails 8.1.2
*   **Database**: PostgreSQL 17 (1 Primary + 2 Replicas)
*   **Caching/State**: Redis 7
*   **Containerization**: Docker & Docker Compose

## 🏗 Architecture

The system implements a **Read/Write Split** architecture at the application layer:

*   **Writes (POST, PUT, DELETE, PATCH)**: Routed directly to the Primary database by default.
*   **Reads (GET, HEAD)**: Routed via the `DatabaseLoadBalancer` to available healthy replicas.

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
The system consists of three PostgreSQL nodes:
*   **Primary**: Handles all writes and acts as a fallback for reads.
*   **Replica 1 & 2**: Dedicated to handling read traffic.
*   **Replication**: Asynchronous streaming replication from Primary to Replicas.

### 2. Health Check Service
A dedicated process (`bin/health_check.rb`) runs alongside the application (container: `rds_health_check`). It:
*   Connects to each DB node every 1 second.
*   Checks connectivity and replication lag.
*   Updates the status of each node in **Redis** (`db_status:replica_1`, etc.).

### 3. Load Balancing Logic
The `DatabaseLoadBalancer` service determines the best replica for **read operations**:
1.  **Check Local Cache**: Returns cached healthy roles if the cache is fresh (< 2s).
2.  **Check Redis**: Fetches current health status from Redis.
3.  **Circuit Breaker**: If Redis is down, it halts Redis checks for 10s (`failure_backoff`) and defaults to using all replicas to prevent cascading failures.
4.  **Role Selection**: Round-robin selection among remaining healthy replicas.
5.  **Fallback**: If no healthy replicas exist, it falls back to the Primary node.

### 4. Request Lifecycle
The `ApplicationController` uses an `around_action` to intelligently route traffic:

```ruby
around_action :switch_database

def switch_database(&block)
  if request.get? || request.head?
    # READS: Use Load Balancer to select a healthy replica
    role = DatabaseLoadBalancer.instance.reading_role
    ApplicationRecord.connected_to(role: role) do
      yield
    end
  else
    # WRITES: Direct to Primary (Default behavior)
    yield
  end
end
```

## 🏁 Getting Started

### Prerequisites
*   Docker & Docker Compose

### Setup

1.  **Start Services**:
    ```bash
    docker-compose up --build
    ```

2.  **Initialize Database**:
    ```bash
    docker-compose run web rails db:prepare
    ```

3.  **Access Application**:
    Open [http://localhost:3000](http://localhost:3000). The page displays connected DB role, IP, and current lag status.

## 🧪 Testing Scenarios

The repository includes several scripts to simulate failures and verify the load balancer's behavior:

| Script | Description |
| :--- | :--- |
| `test_replica1_down.sh` | Stops `postgres-replica1` and verifies traffic shifts to `replica2`. |
| `test_replica1_lag.sh` | Pauses WAL replay on `replica1` to simulate lag > 1s. |
| `test_both_replicas_down.sh` | Stops both replicas to verify fallback to Primary for reads. |
| `test_both_replicas_lag.sh` | Pauses WAL replay on both replicas to simulate lag > 1s on all read nodes. |
| `test_redis_down.sh` | Stops Redis to test the Circuit Breaker functionality. |
| `test_primary_down.sh` | Simulates a primary failure. Reads continue via replicas, but writes will fail. |
| `test_staggered_recovery.sh` | Stops both replicas, then recovers them one at a time to test gradual recovery. |
| `generate_traffic.sh` | Sends concurrent requests to test load distribution. |
| `run_all_tests.sh` | Runs all test scripts sequentially with status reporting. Usage: `./run_all_tests.sh <duration>` |
| `monitor_lb.sh` | Live-monitors the load balancer status endpoint (1s interval) with colored output. |

## 📂 Project Structure

*   `app/services/database_load_balancer.rb`: Core load balancing logic.
*   `bin/health_check.rb`: Independent health monitoring script.
*   `config/database.yml`: Multi-DB configuration.
*   `docker-compose.yml`: Infrastructure definition.
