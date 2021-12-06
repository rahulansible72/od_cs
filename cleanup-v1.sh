#!/bin/bash
# This local variable stops mingw bash from replacing paths with 'C:\Program Files\...', but has no other effect
MSYS_NO_PATHCONV=1

ask() {
    local prompt default reply
    if [[ ${2:-} = 'Y' ]]; then
        prompt='Y/n'
        default='Y'
    elif [[ ${2:-} = 'N' ]]; then
        prompt='y/N'
        default='N'
    else
        prompt='y/n'
        default=''
    fi

    while true; do
        # Ask the question (not using "read -p" as it uses stderr not stdout)
        echo -n "$1 [$prompt] "

        # Read the answer (use /dev/tty in case stdin is redirected from somewhere else)
        read -r reply </dev/tty

        # Did user pressed enter to get the default
        if [[ -z $reply ]]; then
            reply=$default
        fi

        # Check if the reply is valid
        case "$reply" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
    done
}

echo "PVCs using OCS:"
oc get pvc -o=jsonpath='{range .items[?(@.spec.storageClassName=="ocs-storagecluster-ceph-rbd")]}{"Name: "}{@.metadata.name}{" Namespace: "}{@.metadata.namespace}{" Labels: "}{@.metadata.labels}{"\n"}{end}' --all-namespaces|awk '! ( /Namespace: openshift-storage/ && /app:noobaa/ )'
oc get pvc -o=jsonpath='{range .items[?(@.spec.storageClassName=="ocs-storagecluster-cephfs")]}{"Name: "}{@.metadata.name}{" Namespace: "}{@.metadata.namespace}{"\n"}{end}' --all-namespaces
echo
echo "OBCs using OCS:"
oc get obc -o=jsonpath='{range .items[?(@.spec.storageClassName=="openshift-storage.noobaa.io")]}{"Name: "}{@.metadata.name}{" Namespace: "}{@.metadata.namespace}{"\n"}{end}' --all-namespaces

echo "For each PVC/OBC above, check and remove before continuing."
echo "*      oc delete pvc <pvc name> -n <project-name>"
echo "*      oc delete obc <obc name> -n <project name>"

if ask "PVCs/OBCs have been removed? (No will exit)" Y; then
  echo "Continuing with cleanup..."
else
  exit
fi

echo "StorageClasses:"
oc get storageclasses | grep ocs

oc delete storageclass ocs-storagecluster-ceph-rbd ocs-storagecluster-cephfs openshift-storage.noobaa.io --wait=true --timeout=5m

echo "Removing storage cluster and project/namespace..."
OCSCLUSTER_NAME=$(oc -n openshift-storage get storagecluster --no-headers | awk 'NR==1 {print $1}')
oc delete -n openshift-storage storagecluster --all --wait=false
oc patch storagecluster/$OCSCLUSTER_NAME -p '{"metadata":{"finalizers":[]}}' --type=merge
oc delete ns openshift-storage --wait=false

for worker in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do
    echo "Cleaning node $worker ------------------------------------------------------------------------------"
    oc debug node/${worker} -- chroot /host rm -rfv /etc/ceph /etc/ceph-csi-config/ /etc/rook/ /etc/lvm/backup/ /etc/lvm/archive /tmp/operator-sdk-ready /tmp/csi/keys
    oc debug node/${worker} -- chroot /host rm -rfv /var/log/ceph /var/lib/ceph /var/lib/rook /var/lib/kubelet/plugins /var/lib/kubelet/plugins_registry /dev/termination-log
    oc debug node/${worker} -- chroot /host mkdir -p /var/lib/kubelet/plugins
    oc debug node/${worker} -- chroot /host mkdir -p /var/lib/kubelet/plugins_registry
    echo "--------------------------------------------------------------------------------------------------------"
done 

sleep 20
echo "Clearing finalizers..."
oc -n openshift-storage patch persistentvolumeclaim/db-noobaa-db-0 -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch backingstores.noobaa.io/noobaa-default-backing-store -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch bucketclasses.noobaa.io/noobaa-default-bucket-class -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch cephblockpool.ceph.rook.io/ocs-storagecluster-cephblockpool -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch cephcluster.ceph.rook.io/ocs-storagecluster-cephcluster -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch cephfilesystem.ceph.rook.io/ocs-storagecluster-cephfilesystem -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch cephobjectstore.ceph.rook.io/ocs-storagecluster-cephobjectstore -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch cephobjectstoreuser.ceph.rook.io/noobaa-ceph-objectstore-user -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch cephobjectstoreuser.ceph.rook.io/ocs-storagecluster-cephobjectstoreuser -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch noobaa/noobaa -p '{"metadata":{"finalizers":[]}}' --type=merge
oc -n openshift-storage patch storagecluster.ocs.openshift.io/ocs-storagecluster -p '{"metadata":{"finalizers":[]}}' --type=merge
sleep 20
oc delete pods -n openshift-storage --all --force --grace-period=0
sleep 20

if ask "Remove 'workerocs' Machines / MachineSets? (No will skip)" Y; then
    echo "Removing 'workerocs' MachineSets..."
    OCS_MACHINESETS=$(oc get machineset -n openshift-machine-api --no-headers -o custom-columns=NAME:.metadata.name | grep workerocs)
    for ocs_ms in $OCS_MACHINESETS; do
        oc delete -n openshift-machine-api MachineSet $ocs_ms --wait=false
    done

    echo "Patching 'workerocs' machine finalizers for removal..."
    OCS_MACHINES=$(oc get machines -n openshift-machine-api --no-headers | grep workerocs | awk '{print $1}' )
    for ocsworker in $OCS_MACHINES; do
        oc -n openshift-machine-api patch machine/$ocsworker -p '{"metadata":{"finalizers":[]}}' --type=merge
    done
fi

echo "Nodes with openshift-storage label:"
oc get nodes --selector=cluster.ocs.openshift.io/openshift-storage
#OCS_1D_NODES=$(oc get nodes --selector=topology.kubernetes.io/zone=us-east-1d,cluster.ocs.openshift.io/openshift-storage --no-headers | awk '{print $1}')

echo "Clearing OCS labels..."
oc label nodes --all cluster.ocs.openshift.io/openshift-storage-
oc label nodes --all topology.rook.io/rack-

echo "Removing OCS taints..."
oc adm taint nodes --all node.ocs.openshift.io/storage:NoSchedule-

if ask "Scale down 'Compute' node MachineSets/AutoScaler to 0? [Dangerous if other compute workloads present] (No will skip)" N; then
    echo "Patching Machine AutoScaler for Compute MachineSets"
    oc patch -n openshift-machine-api machineautoscaler compute-1a --type json -p='[{ "op": "replace", "path": "/spec/minReplicas", "value": 0 }]'
    oc patch -n openshift-machine-api machineautoscaler compute-1b --type json -p='[{ "op": "replace", "path": "/spec/minReplicas", "value": 0 }]'
    oc patch -n openshift-machine-api machineautoscaler compute-1c --type json -p='[{ "op": "replace", "path": "/spec/minReplicas", "value": 0 }]'
    oc patch -n openshift-machine-api machineautoscaler compute-1d --type json -p='[{ "op": "replace", "path": "/spec/minReplicas", "value": 0 }]'

    echo "Scaling Compute MachineSets"
    oc scale --replicas=0 machineset compute-1a -n openshift-machine-api
    oc scale --replicas=0 machineset compute-1b -n openshift-machine-api
    oc scale --replicas=0 machineset compute-1c -n openshift-machine-api
    oc scale --replicas=0 machineset compute-1d -n openshift-machine-api
fi

echo "Removing OCS CustomResourceDefinitions..."
oc delete cephblockpools.ceph.rook.io ocs-storagecluster-cephblockpool
oc delete cephfilesystems.ceph.rook.io ocs-storagecluster-cephfilesystem
oc delete cephclusters.ceph.rook.io ocs-storagecluster-cephcluster
oc delete crd backingstores.noobaa.io bucketclasses.noobaa.io cephblockpools.ceph.rook.io cephclients.ceph.rook.io cephclusters.ceph.rook.io cephfilesystems.ceph.rook.io cephnfses.ceph.rook.io cephobjectstores.ceph.rook.io cephobjectstoreusers.ceph.rook.io cephobjectrealms.ceph.rook.io cephobjectzones.ceph.rook.io cephobjectzonegroups.ceph.rook.io cephrbdmirrors.ceph.rook.io noobaas.noobaa.io ocsinitializations.ocs.openshift.io  storageclusterinitializations.ocs.openshift.io objectbuckets.objectbucket.io objectbucketclaims.objectbucket.io storageclusters.ocs.openshift.io  --wait=true --timeout=5m

oc delete operator ocs-operator.openshift-storage
