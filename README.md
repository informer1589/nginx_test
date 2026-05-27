# nginx X-Forwarded-For Test Stand

Тестовый стенд для проверки корректной передачи заголовка `X-Forwarded-For` через цепочку nginx-прокси с защитой от его подделки клиентом.

## Задача

При прохождении запроса через несколько nginx-прокси приложение должно:

1. **Получить полную цепочку IP-адресов** — клиента и всех промежуточных nginx.
2. **Не получить поддельный XFF** — заголовок `X-Forwarded-For`, подставленный недобросовестным клиентом, должен быть отброшен.

## Архитектура

```
Клиент
  │
  ├──► nginx1 (8081) ──────────────────────────────► app (8080)
  │         │
  │         ├──► nginx2 (8082) ──────────────────► app (8080)
  │         │
  │         └──► nginx2 (8082) ──► nginx3 (8083) ► app (8080)
  │
  ├──► nginx2 (8082) ──────────────────────────────► app (8080)
  │         │
  │         └──► nginx3 (8083) ──────────────────► app (8080)
  │
  └──► nginx3 (8083) ──────────────────────────────► app (8080)
```

Все сервисы находятся в изолированной Docker-сети `proxy_net` с подсетью `172.28.10.0/24`:

| Сервис | IP в сети    | Внешний порт |
|--------|--------------|--------------|
| app    | 172.28.10.10 | 8080         |
| nginx1 | 172.28.10.11 | 8081         |
| nginx2 | 172.28.10.12 | 8082         |
| nginx3 | 172.28.10.13 | 8083         |

## Принцип работы

Защита от подделки XFF реализована через **явное формирование заголовка** на каждом nginx.

### Первый nginx в цепочке (принимает запрос от клиента)

Заголовок XFF **перезаписывается полностью** — клиентский `$remote_addr` плюс фиксированный IP самого nginx:

```nginx
proxy_set_header X-Forwarded-For "$remote_addr, 172.28.10.11";
```

Любой `X-Forwarded-For`, переданный клиентом, **игнорируется**. В итоге приложение получает только достоверные IP.

### Промежуточный/последний nginx в цепочке (принимает запрос от другого nginx)

Заголовок **расширяется** — к уже накопленной цепочке добавляется IP текущего nginx:

```nginx
proxy_set_header X-Forwarded-For "$proxy_add_x_forwarded_for, 172.28.10.12";
```

`$proxy_add_x_forwarded_for` раскрывается в значение входящего XFF плюс `$remote_addr` предыдущего узла. К этому добавляется явный IP текущего nginx.

### Дополнительный заголовок X-Real-IP

Параллельно передаётся заголовок `X-Real-IP`, сохраняющий оригинальный IP клиента на всём пути:

```nginx
# Первый nginx — фиксирует IP клиента
proxy_set_header X-Real-IP $remote_addr;

# Промежуточные nginx — передают без изменений
proxy_set_header X-Real-IP $http_x_real_ip;
```

## Структура проекта

```
nginx_test/
├── docker-compose.yml
├── nginx1/
│   └── nginx.conf
├── nginx2/
│   └── nginx.conf
├── nginx3/
│   └── nginx.conf
├── README.md
└── run_tests.sh
```

## Быстрый старт

```bash
# Клонировать репозиторий
git clone https://github.com/informer1589/nginx_test.git
cd nginx_test

# Запустить стенд
docker compose up -d

# Убедиться, что все контейнеры запущены
docker compose ps

# Запустить тесты
chmod +x run_tests.sh
./run_tests.sh
```

Для остановки:

```bash
docker compose down
```

## Маршруты (endpoints)

| nginx  | Location             | Маршрут                                    |
|--------|----------------------|--------------------------------------------|
| nginx1 | `/direct`            | nginx1 - app                               |
| nginx1 | `/via-nginx2`        | nginx1 - nginx2 - app                      |
| nginx1 | `/via-nginx2-nginx3` | nginx1 - nginx2 - nginx3 - app             |
| nginx2 | `/direct`            | nginx2 - app                               |
| nginx2 | `/via-nginx3`        | nginx2 - nginx3 - app                      |
| nginx2 | `/from-upstream`     | (входящий от nginx1) - app                 |
| nginx2 | `/to-nginx3`         | (входящий от nginx1) - nginx3 - app        |
| nginx3 | `/direct`            | nginx3 - app                               |
| nginx3 | `/from-upstream`     | (входящий от nginx1/2) - app               |

## Протокол тестирования

Приложение httpbin возвращает JSON, в котором поле `"origin"` содержит значение заголовка `X-Forwarded-For`, полученного приложением.

Замените `localhost` на IP вашего сервера при удалённом тестировании. `<client_ip>` — реальный IP машины, с которой выполняются запросы.

---

### Тест 1. Прямой доступ к приложению (без nginx)

Baseline: приложение без прокси получает только IP клиента.

```bash
curl -s http://localhost:8080/get | jq '.origin'
```

**Ожидаемый результат:**
```
"<client_ip>"
```

---

### Тест 2. Поддельный XFF без nginx (baseline)

Без nginx приложение принимает любой XFF от клиента — это ожидаемое поведение и демонстрация проблемы, которую решает стенд.

```bash
curl -s -H "X-Forwarded-For: 8.8.8.8" http://localhost:8080/get | jq '.origin'
```

**Ожидаемый результат:** поддельный IP принят.
```
"8.8.8.8"
```

---

### Тест 3. Клиент - nginx1 - app

```bash
curl -s http://localhost:8081/direct | jq '.origin'
```

**Ожидаемый результат:**
```
"<client_ip>, 172.28.10.11"
```

---

### Тест 4. Клиент - nginx2 - app

```bash
curl -s http://localhost:8082/direct | jq '.origin'
```

**Ожидаемый результат:**
```
"<client_ip>, 172.28.10.12"
```

---

### Тест 5. Клиент - nginx3 - app

```bash
curl -s http://localhost:8083/direct | jq '.origin'
```

**Ожидаемый результат:**
```
"<client_ip>, 172.28.10.13"
```

---

### Тест 6. Клиент - nginx2 - nginx3 - app

```bash
curl -s http://localhost:8082/via-nginx3 | jq '.origin'
```

**Ожидаемый результат:** IP клиента, nginx2, nginx3.
```
"<client_ip>, 172.28.10.12, 172.28.10.13"
```

---

### Тест 7. Клиент - nginx1 - nginx2 - app

```bash
curl -s http://localhost:8081/via-nginx2 | jq '.origin'
```

**Ожидаемый результат:** IP клиента, nginx1, nginx2.
```
"<client_ip>, 172.28.10.11, 172.28.10.12"
```

---

### Тест 8. Клиент - nginx1 - nginx2 - nginx3 - app

```bash
curl -s http://localhost:8081/via-nginx2-nginx3 | jq '.origin'
```

**Ожидаемый результат:** полная цепочка — IP клиента, nginx1, nginx2, nginx3.
```
"<client_ip>, 172.28.10.11, 172.28.10.12, 172.28.10.13"
```

---

### Тест 9. Поддельный XFF через nginx1 - app ✅ Ключевой тест

Клиент пытается подделать XFF. Nginx1 игнорирует его и формирует заголовок самостоятельно.

```bash
curl -s -H "X-Forwarded-For: 8.8.8.8" http://localhost:8081/direct | jq '.origin'
```

**Ожидаемый результат:** 8.8.8.8 отсутствует.
```
"<client_ip>, 172.28.10.11"
```

---

### Тест 10. Поддельный XFF через цепочку nginx1 - nginx2 - nginx3 - app ✅ Ключевой тест

```bash
curl -s -H "X-Forwarded-For: 8.8.8.8" http://localhost:8081/via-nginx2-nginx3 | jq '.origin'
```

**Ожидаемый результат:** полная цепочка без поддельного IP.
```
"<client_ip>, 172.28.10.11, 172.28.10.12, 172.28.10.13"
```

---

## Сводная таблица результатов

| №  | Маршрут                                        | XFF в приложении                       | Подделка отброшена |
|----|------------------------------------------------|----------------------------------------|--------------------|
| 1  | Прямо на app                                   | `<client>`                             | —                  |
| 2  | Поддельный XFF на app                          | `8.8.8.8`                              | — (нет прокси)     |
| 3  | client - nginx1 - app                          | `<client>, nginx1`                     | —                  |
| 4  | client - nginx2 - app                          | `<client>, nginx2`                     | —                  |
| 5  | client - nginx3 - app                          | `<client>, nginx3`                     | —                  |
| 6  | client - nginx2 - nginx3 - app                 | `<client>, nginx2, nginx3`             | —                  |
| 7  | client - nginx1 - nginx2 - app                 | `<client>, nginx1, nginx2`             | —                  |
| 8  | client - nginx1 - nginx2 - nginx3 - app        | `<client>, nginx1, nginx2, nginx3`     | —                  |
| 9  | **Подделка** - nginx1 - app                    | `<client>, nginx1`                     | ✅                 |
| 10 | **Подделка** - nginx1 - nginx2 - nginx3 - app  | `<client>, nginx1, nginx2, nginx3`     | ✅                 |

## Требования

- Docker Engine 20.10+
- Docker Compose v2
- `curl` и `jq` для запуска тестов

## Используемые образы

- `nginx:1.27-alpine` — обратные прокси
- `kennethreitz/httpbin` — тестовое приложение, отображает входящие заголовки HTTP
