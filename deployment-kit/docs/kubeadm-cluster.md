# Модель кластера kubeadm

Deployment kit использует `kubeadm` как базовый механизм сборки self-hosted Kubernetes-кластера. Такой выбор обусловлен тремя свойствами, важными для ВКР:
- прозрачностью этапов сборки кластера;
- прямым контролем над итоговой топологией;
- совместимостью с переносимой автоматизацией на базе Terraform и Ansible.

## Целевая топология
- 3 управляющих узла
- 2 worker-узла
- Yandex Network Load Balancer перед Kubernetes API
- Yandex Network Load Balancer перед ingress-nginx NodePort

## Последовательность bootstrap
1. Подготовка узлов и установка контейнерного runtime.
2. Установка `kubeadm`, `kubelet` и `kubectl`.
3. Проверка preflight-условий: inventory, swap, sysctl, containerd, Kubernetes packages и свободные control-plane порты.
4. Инициализация первого control-plane узла на основе сгенерированной kubeadm-конфигурации.
5. Проверка доступности локального API и HA endpoint через Yandex Network Load Balancer.
6. Формирование join-команд и certificate-key.
7. Подключение остальных control-plane узлов.
8. Подключение worker-узлов.
9. Установка Calico CNI через Tigera Operator и ожидание rollout `calico-node`.
10. Экспорт kubeconfig для следующих стадий развертывания.
11. Post-bootstrap проверки: Ready nodes, CoreDNS, kube-proxy и etcd endpoint health.

## CNI и NetworkPolicy

Дефолтный CNI — Calico в режиме VXLAN. Он выбран потому, что прикладной контур использует Kubernetes `NetworkPolicy` как часть security baseline. Обычный Flannel поднимает pod-сеть, но не применяет `NetworkPolicy`; такой кластер будет проваливать `make test-security`.

Переменные CNI задаются в `ansible/group_vars/all.yml` и environment overrides:

```yaml
cni_provider: calico
calico_version: "v3.31.4"
pod_subnet: "10.244.0.0/16"
calico_encapsulation: VXLAN
calico_nat_outgoing: Enabled
```

Fallback на внешний manifest остаётся возможным через `cni_provider != calico`, `cni_manifest_url`, `cni_rollout_namespace` и `cni_rollout_resource`, но для production-like стенда он должен использовать CNI с поддержкой NetworkPolicy.

## HA endpoint control plane
`controlPlaneEndpoint` в kubeadm-конфигурации указывает не на отдельный control-plane узел, а на внешний IP сетевого балансировщика Kubernetes API. Это позволяет сохранить доступность API при потере одного управляющего узла и корректно подключать новые control-plane/worker узлы через стабильный адрес.

## Reset без удаления инфраструктуры
Playbook `ansible/playbooks/reset-kubeadm.yml` очищает Kubernetes-состояние на существующих VM:
- выполняет `kubeadm reset -f`;
- удаляет `/etc/kubernetes`, `/var/lib/etcd`, `/var/lib/kubelet`, CNI state, Calico state и Flannel state;
- удаляет интерфейсы `cni0`, `flannel.1`, `vxlan.calico`, `tunl0` и `cali*`;
- очищает iptables/IPVS;
- удаляет локальные bootstrap-артефакты окружения.

Запуск требует явного подтверждения:
```bash
CONFIRM_RESET=vm-dev make kubeadm-reset ENV=vm-dev
```

## Почему в данном проекте выбран kubeadm
`kubeadm` обеспечивает разумный компромисс между полностью ручной сборкой кластера и сильно opinionated-дистрибутивами. Он явно раскрывает логику инициализации control plane, что особенно важно для решения, которое должно быть воспроизводимо и подробно описано в магистерской работе.
