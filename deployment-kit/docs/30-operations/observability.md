# Модель наблюдаемости

Deployment kit устанавливает следующие компоненты:
- Prometheus для сбора метрик;
- Grafana для визуализации;
- Loki для хранения логов;
- Alloy для доставки Pod logs и Kubernetes events в Loki;
- prometheus-blackbox-exporter для активной проверки HTTP/TCP endpoint'ов;
- metrics-server для задач масштабирования.

Контур наблюдаемости используется для демонстрации:
- состояния сервисов;
- состояния узлов;
- потребления ресурсов рабочими нагрузками;
- реакции системы на искусственно созданную нагрузку;
- реакции на отказ worker-узла.

## Источники сигналов

Prometheus собирает:
- стандартные метрики Kubernetes через kube-prometheus-stack;
- метрики узлов через node-exporter;
- состояние объектов Kubernetes через kube-state-metrics;
- метрики ingress-nginx через ServiceMonitor chart'а ingress-nginx;
- метрики kubeadm etcd через дополнительный Prometheus scrape job `kube-etcd`;
- метрики Redis и PostgreSQL через exporter'ы Bitnami chart'ов;
- активные HTTP/TCP пробы через blackbox exporter;
- метрики самого Prometheus, Grafana и Alertmanager.

Loki получает логи Pod'ов и Kubernetes events через Alloy. Grafana подключает два datasource: `Prometheus` и `Loki`.

Alloy разворачивается DaemonSet'ом, но не читает hostPath `/var/log`: конфигурация использует `loki.source.kubernetes` и ограничивает discovery Pod'ами текущего узла через `spec.nodeName`. Это снижает привилегии коллектора логов и убирает необходимость в privileged/root доступе к файловой системе узла.

## Grafana dashboards

Deployment kit поставляет собственную папку Grafana `Deployment Kit` с dashboards:

- `Deployment Kit / Cluster Overview` — состояние узлов, Pod'ов, CPU, memory, рестарты, latency Kubernetes API;
- `Deployment Kit / Applications` — доступность Deployment'ов namespace `app`, HPA, CPU/memory по Pod'ам, ingress request rate/latency и ошибки из Loki;
- `Deployment Kit / Endpoints` — blackbox health для внутренних сервисов, ingress endpoints, GitLab, Registry, Vault, PostgreSQL и Redis;
- `Deployment Kit / Redis and PostgreSQL` — готовность StatefulSet'ов, TCP probes, PostgreSQL connections/transactions, Redis clients/commands, CPU/RAM, PVC free space и ошибки из Loki;
- `Deployment Kit / etcd` — scrape targets etcd, наличие лидера, leader changes, размер БД, fsync/backend commit latency, proposals и peer round-trip;
- `Deployment Kit / Platform` — Vault, GitLab, PVC, активные alerts, ошибки платформенных namespace.

Dashboards поставляются ConfigMap'ом `observability/deployment-kit-grafana-dashboards` с label `grafana_dashboard=1`. Grafana sidecar автоматически импортирует их при `make deploy-platform`.

Для kubeadm etcd Ansible задаёт `listen-metrics-urls=http://0.0.0.0:2381` в kubeadm ClusterConfiguration. Prometheus находит static pods etcd через Kubernetes pod discovery в namespace `kube-system` и скрейпит `pod_ip:2381` с job label `kube-etcd`. Если dashboard `Deployment Kit / etcd` показывает `no data`, проверьте, что кластер был пересобран после обновления kubeadm template и что в Prometheus Targets есть job `kube-etcd`.

## Endpoint probing

Blackbox exporter проверяет:

- `api.app.svc.cluster.local:8081/health`;
- `gateway.app.svc.cluster.local:8080/health`;
- `frontend.app.svc.cluster.local:8080/health`;
- ingress-маршруты `app.pkhco.ru` и `gateway.pkhco.ru` через service ingress-nginx;
- `gitlab.pkhco.ru/users/sign_in`;
- `registry.pkhco.ru/v2/`;
- Vault health endpoint;
- TCP-доступность PostgreSQL и Redis.

ServiceMonitor'ы для probes применяются по стадиям:
- `platform-probes.yaml` применяет `make deploy-platform`;
- `gitlab-probes.yaml` применяет `make deploy-gitlab`;
- `app-probes.yaml` применяет `make deploy-apps`.

Для дефолтного публичного профиля probes проверяют `app.pkhco.ru`, `gateway.pkhco.ru`, `gitlab.pkhco.ru` и `registry.pkhco.ru`. При публикации на другом публичном домене deploy-скрипты подставляют текущий `APP_DOMAIN`.

Такой порядок исключает постоянные ложные срабатывания по GitLab/app endpoint'ам до того, как эти компоненты установлены.

Для таких проверок в namespace `app` добавлены отдельные NetworkPolicy-разрешения из namespace `observability`. Это сохраняет default-deny модель и открывает только нужные порты мониторинга.

NetworkPolicy-разрешения реально применяются только при CNI с policy enforcement. Дефолтный kubeadm bootstrap использует Calico; Flannel-only кластер оставлен только как fallback и не проходит security baseline.

## Alert rules

PrometheusRule `observability/deployment-kit-platform-alerts` добавляет проверки:

- node not ready;
- высокий CPU/memory usage кластера;
- недоступные реплики приложений;
- CrashLoopBackOff и частые рестарты;
- ingress 5xx;
- endpoint down/slow;
- истечение TLS-сертификата;
- недоступные реплики Vault/GitLab;
- недоступность Redis/PostgreSQL;
- отказ TCP-probe datastore'ов;
- заполнение PVC.

## Доступ к Grafana

Локальный port-forward:

```bash
export KUBECONFIG=.artifacts/vm-dev/admin.conf
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
```

После этого Grafana доступна на `http://127.0.0.1:3000`.

Логин берётся из `GRAFANA_ADMIN_USER`, пароль — из `GRAFANA_ADMIN_PASSWORD` или Kubernetes Secret:

```bash
kubectl -n observability get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 --decode
echo
```

## Проверка мониторинга

```bash
kubectl -n observability get pods
kubectl -n observability rollout status daemonset/alloy --timeout=300s
kubectl -n observability get servicemonitor -l deployment-kit/component=alloy
kubectl -n observability get servicemonitor -l deployment-kit/component=endpoint-probe
kubectl -n observability get prometheusrule deployment-kit-platform-alerts
kubectl -n observability get configmap deployment-kit-grafana-dashboards
```

Полная интеграционная проверка:

```bash
make test-integration ENV=vm-dev
```
