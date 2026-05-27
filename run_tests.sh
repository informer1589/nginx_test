#!/usr/bin/env bash

echo "============================"
echo "Тест 1: без nginx — origin содержит только IP клиента"
echo "============================"
curl -s http://localhost:8080/get | jq '.origin'

echo "============================"
echo "Тест 2: без nginx — поддельный XFF принимается"
echo "============================"
curl -s -H "X-Forwarded-For: 8.8.8.8" http://localhost:8080/get | jq '.origin'

echo "============================"
echo "Тест 3: клиент - nginx1 - app"
echo "============================"
curl -s http://localhost:8081/direct | jq '.origin'

echo "============================"
echo "Тест 4: клиент - nginx2 - app"
echo "============================"
curl -s http://localhost:8082/direct | jq '.origin'

echo "============================"
echo "Тест 5: клиент - nginx3 - app"
echo "============================"
curl -s http://localhost:8083/direct | jq '.origin'

echo "============================"
echo "Тест 6: клиент - nginx2 - nginx3 - app"
echo "============================"
curl -s http://localhost:8082/via-nginx3 | jq '.origin'

echo "============================"
echo "Тест 7: клиент - nginx1 - nginx2 - app"
echo "============================"
curl -s http://localhost:8081/via-nginx2 | jq '.origin'

echo "============================"
echo "Тест 8: клиент - nginx1 - nginx2 - nginx3 - app"
echo "============================"
curl -s http://localhost:8081/via-nginx2-nginx3 | jq '.origin'

echo "============================"
echo "Тест 9: поддельный XFF через nginx1 - app"
echo "============================"
curl -s -H "X-Forwarded-For: 8.8.8.8" http://localhost:8081/direct | jq '.origin'

echo "============================"
echo "Тест 10: поддельный XFF через цепочку клиент-nginx1-nginx2-nginx3-app"
echo "============================"
curl -s -H "X-Forwarded-For: 8.8.8.8" http://localhost:8081/via-nginx2-nginx3 | jq '.origin'

