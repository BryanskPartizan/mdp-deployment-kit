# Проверка состояния control plane

Кластер использует три управляющих узла. Проверка включает:
- контроль результата `kubectl get nodes` и статуса Ready;
- анализ `kubectl get pods -n kube-system` для control-plane компонентов;
- подтверждение доступности API-сервера через control plane endpoint;
- проверку состояния pod `etcd` и `controller-manager`.
