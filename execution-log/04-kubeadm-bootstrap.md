# Этап 4. Bootstrap Kubernetes-кластера через kubeadm

## Назначение этапа

Цель этапа — собрать self-hosted Kubernetes-кластер на созданных ВМ: подготовить ОС, установить
containerd, kubeadm/kubelet/kubectl, инициализировать первый control plane, подключить остальные
control plane и worker-узлы, установить Calico CNI, экспортировать kubeconfig и проверить готовность
control plane.

<span style="color:#16833a"><strong>Итог этапа:</strong></span> Kubernetes-кластер из 5 узлов
развернут, все узлы `Ready`, `readyz check passed`.

## 4.1. Запуск Ansible bootstrap

### Команда

```bash
make kubeadm-bootstrap ENV=vm-dev
```

### Зачем запускалась

Команда запускает `ci/scripts/ansible-kubeadm-bootstrap.sh vm-dev`, который использует
`ansible/playbooks/site.yml` и inventory из Terraform outputs. Это основной шаг сборки Kubernetes.

### Вывод: старт playbook

```text
./ci/scripts/ansible-kubeadm-bootstrap.sh vm-dev

PLAY [Подготовка операционной системы]

TASK [Gathering Facts]
ok: [mdp-worker-01]
ok: [mdp-cp-01]
ok: [mdp-worker-02]
ok: [mdp-cp-02]
ok: [mdp-cp-03]
```

## 4.2. Подготовка ОС

### Зачем выполнялась

Kubernetes требует отключенного swap, корректных sysctl-настроек, установленного базового набора
пакетов и предсказуемых hostname.

### Вывод

```text
TASK [common : Обновление apt-кеша на узлах семейства Debian]
changed: [mdp-worker-02]
changed: [mdp-worker-01]
changed: [mdp-cp-02]
changed: [mdp-cp-03]
changed: [mdp-cp-01]

TASK [common : Установка базовых пакетов]
changed: [mdp-worker-02]
changed: [mdp-worker-01]
changed: [mdp-cp-03]
changed: [mdp-cp-02]
changed: [mdp-cp-01]

TASK [common : Немедленное отключение swap]
skipping: [mdp-cp-02]
skipping: [mdp-cp-01]
skipping: [mdp-cp-03]
skipping: [mdp-worker-01]
skipping: [mdp-worker-02]

TASK [common : Отключение swap в fstab]
ok: [mdp-cp-02]
ok: [mdp-worker-02]
ok: [mdp-cp-01]
ok: [mdp-cp-03]
ok: [mdp-worker-01]

TASK [common : Установка hostname из inventory при наличии fqdn]
changed: [mdp-cp-01]
changed: [mdp-worker-02]
changed: [mdp-cp-02]
changed: [mdp-worker-01]
changed: [mdp-cp-03]

TASK [common : Развёртывание конфигурации sysctl]
changed: [mdp-cp-01]
changed: [mdp-worker-02]
changed: [mdp-cp-02]
changed: [mdp-worker-01]
changed: [mdp-cp-03]

RUNNING HANDLER [common : reload sysctl]
changed: [mdp-cp-02]
changed: [mdp-worker-02]
changed: [mdp-worker-01]
changed: [mdp-cp-03]
changed: [mdp-cp-01]
```

## 4.3. Установка containerd

### Зачем выполнялась

containerd используется как CRI runtime для kubelet.

### Вывод

```text
PLAY [Установка контейнерного runtime]

TASK [container_runtime : Install containerd package]
changed: [mdp-worker-01]
changed: [mdp-worker-02]
changed: [mdp-cp-03]
changed: [mdp-cp-01]
changed: [mdp-cp-02]

TASK [container_runtime : Ensure containerd config directory exists]
changed: [mdp-cp-01]
changed: [mdp-cp-02]
changed: [mdp-worker-02]
changed: [mdp-cp-03]
changed: [mdp-worker-01]

TASK [container_runtime : Генерация конфигурации containerd по умолчанию при отсутствии файла]
changed: [mdp-cp-01]
changed: [mdp-cp-02]
changed: [mdp-cp-03]
changed: [mdp-worker-01]
changed: [mdp-worker-02]

TASK [container_runtime : Включение SystemdCgroup в конфигурации containerd]
changed: [mdp-cp-01]
changed: [mdp-cp-02]
changed: [mdp-cp-03]
changed: [mdp-worker-01]
changed: [mdp-worker-02]

TASK [container_runtime : Enable and restart containerd]
changed: [mdp-cp-01]
changed: [mdp-cp-02]
changed: [mdp-cp-03]
changed: [mdp-worker-02]
changed: [mdp-worker-01]
```

### Предупреждение

```text
[WARNING]: Module remote_tmp /root/.ansible/tmp did not exist and was created with a mode of 0700...
```

Это предупреждение Ansible о временном каталоге root. Оно не является блокирующим: playbook
продолжил выполнение, containerd был установлен и перезапущен.

## 4.4. Установка Kubernetes-пакетов

### Зачем выполнялась

На всех узлах устанавливаются `kubeadm`, `kubelet` и `kubectl`, после чего версии фиксируются
через hold.

### Вывод

```text
PLAY [Install kubeadm, kubelet and kubectl]

TASK [kubernetes_packages : Добавление APT-репозитория Kubernetes key]
changed: [mdp-cp-02]
changed: [mdp-cp-03]
changed: [mdp-cp-01]
changed: [mdp-worker-01]
changed: [mdp-worker-02]

TASK [kubernetes_packages : Add Kubernetes repository]
changed: [mdp-cp-01]
changed: [mdp-cp-02]
changed: [mdp-cp-03]
changed: [mdp-worker-01]
changed: [mdp-worker-02]

TASK [kubernetes_packages : Установка пакетов Kubernetes]
changed: [mdp-worker-01]
changed: [mdp-worker-02]
changed: [mdp-cp-02]
changed: [mdp-cp-01]
changed: [mdp-cp-03]

TASK [kubernetes_packages : Фиксация версий пакетов Kubernetes]
changed: [mdp-cp-02] => (item=kubelet)
changed: [mdp-worker-01] => (item=kubelet)
changed: [mdp-worker-02] => (item=kubelet)
changed: [mdp-cp-03] => (item=kubelet)
changed: [mdp-cp-01] => (item=kubelet)
changed: [mdp-cp-02] => (item=kubeadm)
changed: [mdp-worker-01] => (item=kubeadm)
changed: [mdp-cp-03] => (item=kubeadm)
changed: [mdp-worker-02] => (item=kubeadm)
changed: [mdp-cp-01] => (item=kubeadm)
changed: [mdp-cp-02] => (item=kubectl)
changed: [mdp-worker-01] => (item=kubectl)
changed: [mdp-cp-03] => (item=kubectl)
changed: [mdp-worker-02] => (item=kubectl)
changed: [mdp-cp-01] => (item=kubectl)

TASK [kubernetes_packages : Включение сервиса kubelet service]
changed: [mdp-cp-02]
changed: [mdp-worker-02]
changed: [mdp-cp-03]
changed: [mdp-worker-01]
changed: [mdp-cp-01]
```

## 4.5. Проверки готовности перед kubeadm

### Зачем выполнялись

Preflight-блок проверяет inventory, уникальность `node_ip`, ОС, swap, kernel modules, sysctl,
containerd, наличие kubeadm/kubectl/kubelet и свободные control plane порты.

### Вывод

```text
PLAY [Проверка готовности узлов к kubeadm bootstrap]

TASK [kubeadm_preflight : Проверка обязательных переменных kubeadm]
ok: [mdp-cp-01] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [mdp-cp-02] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [mdp-cp-03] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [mdp-worker-01] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [mdp-worker-02] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [kubeadm_preflight : Проверка HA-топологии inventory]
ok: [mdp-cp-01 -> localhost] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [kubeadm_preflight : Проверка уникальности node_ip]
ok: [mdp-cp-01 -> localhost] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [kubeadm_preflight : Проверка Calico podSubnet]
ok: [mdp-cp-01] => {
    "changed": false,
    "msg": "All assertions passed"
}
```

## 4.6. Инициализация первого control plane

### Зачем выполнялась

Первый control plane создает кластер, локальный API, etcd member и join-команды для остальных
узлов.

### Вывод

```text
PLAY [Инициализация первого control-plane узла node]

TASK [kubeadm_init : Генерация конфигурации kubeadm init]
changed: [mdp-cp-01]

TASK [kubeadm_init : Выполнение kubeadm init]
changed: [mdp-cp-01]

TASK [kubeadm_init : Ожидание готовности локального Kubernetes API]
ok: [mdp-cp-01]

TASK [kubeadm_init : Ожидание доступности HA endpoint Kubernetes API]
ok: [mdp-cp-01]

TASK [kubeadm_init : Получение join-команды для worker-узлов]
ok: [mdp-cp-01]

TASK [kubeadm_init : Получение certificate-key для подключения control plane]
ok: [mdp-cp-01]

TASK [kubeadm_init : Сохранение join-команды worker-узлов локально]
changed: [mdp-cp-01 -> localhost]

TASK [kubeadm_init : Сохранение join-команды control-plane локально]
changed: [mdp-cp-01 -> localhost]
```

### Примечание по секретам

Join-команды и `certificate-key` не приводятся в отчете: они являются bootstrap-секретами.

## 4.7. Подключение остальных control plane и worker-узлов

### Зачем выполнялось

Оставшиеся control plane подключаются к HA control plane, worker-узлы подключаются как рабочие
узлы для прикладных workload.

### Вывод

```text
PLAY [Join remaining control plane nodes]

TASK [kubeadm_join_control_plane : Join node to control plane]
changed: [mdp-cp-02]
changed: [mdp-cp-03]

TASK [kubeadm_join_control_plane : Проверка kubelet после join control-plane]
ok: [mdp-cp-02] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [mdp-cp-03] => {
    "changed": false,
    "msg": "All assertions passed"
}

PLAY [Подключение worker-узлов]

TASK [kubeadm_join_worker : Join node as worker]
changed: [mdp-worker-01]
changed: [mdp-worker-02]

TASK [kubeadm_join_worker : Проверка kubelet после join worker]
ok: [mdp-worker-01] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [mdp-worker-02] => {
    "changed": false,
    "msg": "All assertions passed"
}
```

## 4.8. Установка Calico CNI

### Зачем выполнялась

Calico обеспечивает Pod-сеть и исполнение Kubernetes NetworkPolicy. Это необходимо для security
tests и изоляции прикладного namespace.

### Вывод

```text
PLAY [Установка CNI plugin]

TASK [cni : Установка Calico operator CRD]
changed: [mdp-cp-01]

TASK [cni : Ожидание регистрации Calico Installation CRD]
ok: [mdp-cp-01]

TASK [cni : Установка Calico operator]
changed: [mdp-cp-01]

TASK [cni : Ожидание готовности Tigera operator]
ok: [mdp-cp-01]

TASK [cni : Генерация Calico Installation custom resource]
changed: [mdp-cp-01]

TASK [cni : Применение Calico Installation custom resource]
changed: [mdp-cp-01]

TASK [cni : Ожидание создания namespace calico-system]
FAILED - RETRYING: [mdp-cp-01]: Ожидание создания namespace calico-system (30 retries left).
ok: [mdp-cp-01]

TASK [cni : Ожидание rollout Calico node DaemonSet]
FAILED - RETRYING: [mdp-cp-01]: Ожидание rollout Calico node DaemonSet (30 retries left).
ok: [mdp-cp-01]

TASK [cni : Ожидание готовности Calico controllers]
ok: [mdp-cp-01]
```

Повторные попытки не являются ошибкой этапа: Ansible ожидал появления namespace и rollout DaemonSet.
После ожидания оба условия завершились `ok`.

## 4.9. Экспорт kubeconfig и post-bootstrap checks

### Вывод

```text
PLAY [Export kubeconfig and cluster tools]

TASK [kubeconfig : Fetch admin kubeconfig to local artifacts]
changed: [mdp-cp-01]

TASK [kubeconfig : Фиксация HA endpoint в локальном kubeconfig]
ok: [mdp-cp-01 -> localhost]

TASK [kubeconfig : Ограничение прав на локальный kubeconfig]
changed: [mdp-cp-01 -> localhost]

PLAY [Apply post-bootstrap configuration]

TASK [post_bootstrap : Label worker nodes for application workloads]
ok: [mdp-cp-01] => (item=mdp-worker-01)
ok: [mdp-cp-01] => (item=mdp-worker-02)

TASK [post_bootstrap : Wait for nodes to become Ready]
ok: [mdp-cp-01]

TASK [post_bootstrap : Ожидание готовности CoreDNS]
ok: [mdp-cp-01]

TASK [post_bootstrap : Ожидание готовности kube-proxy]
ok: [mdp-cp-01]

TASK [post_bootstrap : Проверка quorum etcd через endpoint health]
ok: [mdp-cp-01]
```

## 4.10. Итог Ansible playbook

### Вывод

```text
PLAY RECAP
mdp-cp-01                  : ok=79   changed=31   unreachable=0    failed=0    skipped=5    rescued=0    ignored=0
mdp-cp-02                  : ok=49   changed=21   unreachable=0    failed=0    skipped=3    rescued=0    ignored=0
mdp-cp-03                  : ok=49   changed=21   unreachable=0    failed=0    skipped=3    rescued=0    ignored=0
mdp-worker-01              : ok=49   changed=21   unreachable=0    failed=0    skipped=3    rescued=0    ignored=0
mdp-worker-02              : ok=49   changed=21   unreachable=0    failed=0    skipped=3    rescued=0    ignored=0
```

## 4.11. Проверка Kubernetes nodes

### Команды

```bash
export KUBECONFIG=.artifacts/vm-dev/admin.conf
kubectl get nodes -o wide
```

### Зачем запускались

Команды переключают kubectl на новый kubeconfig и проверяют регистрацию всех узлов.

### Вывод

```text
NAME                                 STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
mdp-cp-01.ru-central1.internal       Ready    control-plane   3m22s   v1.29.3   10.10.10.10   <none>        Ubuntu 22.04.5 LTS   5.15.0-177-generic   containerd://2.2.1
mdp-cp-02.ru-central1.internal       Ready    control-plane   2m35s   v1.29.3   10.10.10.11   <none>        Ubuntu 22.04.5 LTS   5.15.0-177-generic   containerd://2.2.1
mdp-cp-03.ru-central1.internal       Ready    control-plane   2m33s   v1.29.3   10.10.10.12   <none>        Ubuntu 22.04.5 LTS   5.15.0-177-generic   containerd://2.2.1
mdp-worker-01.ru-central1.internal   Ready    worker          2m8s    v1.29.3   10.10.10.20   <none>        Ubuntu 22.04.5 LTS   5.15.0-177-generic   containerd://2.2.1
mdp-worker-02.ru-central1.internal   Ready    worker          2m8s    v1.29.3   10.10.10.21   <none>        Ubuntu 22.04.5 LTS   5.15.0-177-generic   containerd://2.2.1
```

## 4.12. Проверка системных Pod'ов

### Команда

```bash
kubectl -n kube-system get pods -o wide
```

### Зачем запускалась

Команда подтверждает, что control plane, etcd, scheduler, controller-manager, CoreDNS и kube-proxy
находятся в рабочем состоянии.

### Вывод

```text
NAME                                                     READY   STATUS    RESTARTS   AGE     IP              NODE
coredns-76f75df574-q97vq                                 1/1     Running   0          3m15s   10.244.101.69   mdp-cp-03.ru-central1.internal
coredns-76f75df574-z698p                                 1/1     Running   0          3m15s   10.244.101.67   mdp-cp-03.ru-central1.internal
etcd-mdp-cp-01.ru-central1.internal                      1/1     Running   0          3m23s   10.10.10.10     mdp-cp-01.ru-central1.internal
etcd-mdp-cp-02.ru-central1.internal                      1/1     Running   0          2m35s   10.10.10.11     mdp-cp-02.ru-central1.internal
etcd-mdp-cp-03.ru-central1.internal                      1/1     Running   0          2m30s   10.10.10.12     mdp-cp-03.ru-central1.internal
kube-apiserver-mdp-cp-01.ru-central1.internal            1/1     Running   0          3m23s   10.10.10.10     mdp-cp-01.ru-central1.internal
kube-apiserver-mdp-cp-02.ru-central1.internal            1/1     Running   0          2m35s   10.10.10.11     mdp-cp-02.ru-central1.internal
kube-apiserver-mdp-cp-03.ru-central1.internal            1/1     Running   0          2m32s   10.10.10.12     mdp-cp-03.ru-central1.internal
kube-controller-manager-mdp-cp-01.ru-central1.internal   1/1     Running   0          3m23s   10.10.10.10     mdp-cp-01.ru-central1.internal
kube-controller-manager-mdp-cp-02.ru-central1.internal   1/1     Running   0          2m35s   10.10.10.11     mdp-cp-02.ru-central1.internal
kube-controller-manager-mdp-cp-03.ru-central1.internal   1/1     Running   0          2m32s   10.10.10.12     mdp-cp-03.ru-central1.internal
kube-proxy-cfmhj                                         1/1     Running   0          2m11s   10.10.10.21     mdp-worker-02.ru-central1.internal
kube-proxy-fhgpw                                         1/1     Running   0          3m15s   10.10.10.10     mdp-cp-01.ru-central1.internal
kube-proxy-fjhpm                                         1/1     Running   0          2m36s   10.10.10.12     mdp-cp-03.ru-central1.internal
kube-proxy-msf4n                                         1/1     Running   0          2m38s   10.10.10.11     mdp-cp-02.ru-central1.internal
kube-proxy-rg8l6                                         1/1     Running   0          2m11s   10.10.10.20     mdp-worker-01.ru-central1.internal
kube-scheduler-mdp-cp-01.ru-central1.internal            1/1     Running   0          3m24s   10.10.10.10     mdp-cp-01.ru-central1.internal
kube-scheduler-mdp-cp-02.ru-central1.internal            1/1     Running   0          2m35s   10.10.10.11     mdp-cp-02.ru-central1.internal
kube-scheduler-mdp-cp-03.ru-central1.internal            1/1     Running   0          2m32s   10.10.10.12     mdp-cp-03.ru-central1.internal
```

## 4.13. Проверка готовности Kubernetes API

### Команда

```bash
kubectl get --raw='/readyz?verbose'
```

### Зачем запускалась

Команда проверяет health/readiness Kubernetes API server и post-start hooks. Это контрольная
проверка готовности control plane.

### Вывод

```text
[+]ping ok
[+]log ok
[+]etcd ok
[+]etcd-readiness ok
[+]informer-sync ok
[+]poststarthook/start-kube-apiserver-admission-initializer ok
[+]poststarthook/generic-apiserver-start-informers ok
[+]poststarthook/priority-and-fairness-config-consumer ok
[+]poststarthook/priority-and-fairness-filter ok
[+]poststarthook/storage-object-count-tracker-hook ok
[+]poststarthook/start-apiextensions-informers ok
[+]poststarthook/start-apiextensions-controllers ok
[+]poststarthook/crd-informer-synced ok
[+]poststarthook/start-service-ip-repair-controllers ok
[+]poststarthook/rbac/bootstrap-roles ok
[+]poststarthook/scheduling/bootstrap-system-priority-classes ok
[+]poststarthook/priority-and-fairness-config-producer ok
[+]poststarthook/start-system-namespaces-controller ok
[+]poststarthook/bootstrap-controller ok
[+]poststarthook/start-cluster-authentication-info-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-garbage-collector ok
[+]poststarthook/start-legacy-token-tracking-controller ok
[+]poststarthook/aggregator-reload-proxy-client-cert ok
[+]poststarthook/start-kube-aggregator-informers ok
[+]poststarthook/apiservice-registration-controller ok
[+]poststarthook/apiservice-status-available-controller ok
[+]poststarthook/kube-apiserver-autoregistration ok
[+]autoregister-completion ok
[+]poststarthook/apiservice-openapi-controller ok
[+]poststarthook/apiservice-openapiv3-controller ok
[+]poststarthook/apiservice-discovery-controller ok
[+]shutdown ok
readyz check passed
```

## Схема этапа

```mermaid
flowchart LR
    A[Ansible inventory] --> B[OS prereqs]
    B --> C[containerd]
    C --> D[kubeadm/kubelet/kubectl]
    D --> E[kubeadm init mdp-cp-01]
    E --> F[join mdp-cp-02/mdp-cp-03]
    F --> G[join workers]
    G --> H[Calico CNI]
    H --> I[admin.conf + readyz]
```

## Результат этапа

<span style="color:#16833a"><strong>Успешно.</strong></span> Bootstrap завершился без `failed` и
`unreachable`. Кластер готов к установке платформенных сервисов.

