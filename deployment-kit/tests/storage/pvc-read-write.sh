#!/usr/bin/env bash
# Проверяет динамическое выделение local-path PVC и сохранение данных между Pod'ами.
set -euo pipefail

TEST_IMAGE=${STORAGE_TEST_IMAGE:-busybox:1.36}
PVC_NAME=${STORAGE_TEST_PVC:-dk-storage-probe}
WRITER_POD=${STORAGE_WRITER_POD:-dk-storage-writer}
READER_POD=${STORAGE_READER_POD:-dk-storage-reader}
TEST_PAYLOAD="deployment-kit-storage-ok"

cleanup() {
  kubectl -n app delete pod "$WRITER_POD" "$READER_POD" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl -n app delete pvc "$PVC_NAME" --ignore-not-found >/dev/null 2>&1 || true
}

cleanup
trap cleanup EXIT

kubectl get storageclass local-path

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: app
spec:
  storageClassName: local-path
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 128Mi
YAML

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${WRITER_POD}
  namespace: app
  labels:
    dk-test: storage
spec:
  restartPolicy: Never
  containers:
    - name: writer
      image: ${TEST_IMAGE}
      command: ["sh", "-ec", "echo '${TEST_PAYLOAD}' > /data/probe.txt && cat /data/probe.txt"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
YAML

kubectl -n app wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${WRITER_POD}" --timeout=300s
kubectl -n app logs "$WRITER_POD"
kubectl -n app delete pod "$WRITER_POD" --wait=true

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${READER_POD}
  namespace: app
  labels:
    dk-test: storage
spec:
  restartPolicy: Never
  containers:
    - name: reader
      image: ${TEST_IMAGE}
      command: ["sh", "-ec", "grep -qx '${TEST_PAYLOAD}' /data/probe.txt && cat /data/probe.txt"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
YAML

kubectl -n app wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${READER_POD}" --timeout=300s
kubectl -n app logs "$READER_POD"

