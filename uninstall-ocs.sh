#!/bin/bash

# List StorageClasses
oc get storageclasses --no-headers

# List PVCs attatched to ocs-storagecluster-ceph-rbd
oc get pvc -o=jsonpath='{range .items[?(@.spec.storageClassName=="ocs-storagecluster-ceph-rbd")]}{"Name: "}{@.metadata.name}{" Namespace: "}{@.metadata.namespace}{" Labels: "}{@.metadata.labels}{"\n"}{end}' --all-namespaces|awk '! ( /Namespace: openshift-storage/ && /app:noobaa/ )'

# List PVCs attached to ocs-storagecluster-cephfs
oc get pvc -o=jsonpath='{range .items[?(@.spec.storageClassName=="ocs-storagecluster-cephfs")]}{"Name: "}{@.metadata.name}{" Namespace: "}{@.metadata.namespace}{"\n"}{end}' --all-namespaces

# List PVCs attached to openshift-storage.noobaa.io
oc get obc -o=jsonpath='{range .items[?(@.spec.storageClassName=="openshift-storage.noobaa.io")]}{"Name: "}{@.metadata.name}{" Namespace: "}{@.metadata.namespace}{"\n"}{end}' --all-namespaces

# For each PVC above, delete PVCs and/or OBCs attached:
#*      oc delete pvc <pvc name> -n <project-name>
#*      oc delete obc <obc name> -n <project name>

#List backing volumes for Storage Classes
#   for sc in $(oc get storageclass|grep 'kubernetes.io/no-provisioner' |grep -E $(oc get storagecluster -n openshift-storage -o jsonpath='{ .items[*].spec.storageDeviceSets[*].dataPVCTemplate.spec.storageClassName}' | sed 's/ /|/g')| awk '{ print $1 }');

for sc in $(oc get storageclass|grep 'openshift-storage' |grep -E $(oc get storagecluster -n openshift-storage -o jsonpath='{ .items[*].spec.storageDeviceSets[*].dataPVCTemplate.spec.storageClassName}' | sed 's/ /|/g')| awk '{ print $1 }');
do
    echo -n "StorageClass: $sc ";
    oc get storageclass $sc -o jsonpath=" { 'LocalVolume: ' }{ .metadata.labels['local\.storage\.openshift\.io/owner-name'] } { '\n' }";
done

# Delete the StorageCluster object.
oc delete -n openshift-storage storagecluster --all --wait=true

# Remove CustomResourceDefinitions
oc delete crd backingstores.noobaa.io bucketclasses.noobaa.io cephblockpools.ceph.rook.io cephclusters.ceph.rook.io cephfilesystems.ceph.rook.io cephnfses.ceph.rook.io cephobjectstores.ceph.rook.io cephobjectstoreusers.ceph.rook.io noobaas.noobaa.io ocsinitializations.ocs.openshift.io  storageclusterinitializations.ocs.openshift.io objectbuckets.objectbucket.io objectbucketclaims.objectbucket.io storageclusters.ocs.openshift.io  --wait=true --timeout=5m

#Delete CSVs in openshift-storage namespace
for i in $(oc get -n openshift-storage csv -o jsonpath='{ .items[*].metadata.name  }'); do oc delete csv ${i} -n openshift-storage; done

# Delete remaining pods, deamonsets, replicasets, deployment.apps, and services
oc delete pods,jobs,ds,rs,statefulset,hpa,deployment.apps,jobs,service,route --all -n openshift-storage
   # oc delete ds --all -n openshift-storage
   # oc delete rs --all -n openshift-storage
   # oc delete statefulset --all -n openshift-storage
   # oc delete hpa --all -n openshift-storage
   # oc delete deployment.apps --all -n openshift-storage
   # oc delete jobs --all -n openshift-storage
   # oc delete service --all -n openshift-storage
   # oc delete route --all -n openshift-storage

#Verify no resources in openshift storage namespace
oc get all -n openshift-storage

# Delete the namespace and wait till the deletion is complete.
oc delete project openshift-storage --wait=true --timeout=2m
oc delete namespace openshift-storage


# # Clean up the storage operator artifacts on each node.
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /var/lib/rook; done
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /var/lib/kubelet/plugins; done
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /var/lib/kubelet/plugins_registry; done

# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /etc/lvm/backup/; done
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /etc/lvm/archive/; done


# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /var/lib/ceph; done
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /etc/ceph; done

# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /var/log/ceph; done
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /dev/termination-log; done
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /tmp/operator-sdk-ready; done
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /etc/ceph-csi-config/; done
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /tmp/csi/keys; done
# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /etc/rook/; done


# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host mkdir -p /var/lib/kubelet/plugins; done

# for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host mkdir -p /var/lib/kubelet/plugins_registry; done


# Delete the storage classes with an openshift-storage provisioner listed in step 1.
oc delete storageclass ocs-storagecluster-ceph-rbd ocs-storagecluster-cephfs openshift-storage.noobaa.io --wait=true --timeout=5m

# # Delete the local volume
# LV=local-block
# SC=localblock

# # List and note the devices to be cleaned up later.
# oc get localvolume -n local-storage $LV -o jsonpath='{ .spec.storageClassDevices[*].devicePaths[*] }'

# # Delete the local volume resource.
# oc delete localvolume -n local-storage --wait=true $LV

# Delete the remaining PVs and StorageClasses if they exist.
# oc delete pv -l storage.openshift.com/local-volume-owner-name=${LV} --wait --timeout=5m
# oc delete storageclass $SC --wait --timeout=5m

# # Delete local-storage
# oc delete pods,services,deployment.apps,replicaset.apps --all -n local-storage
# oc delete project local-storage --wait=true --timeout=5m
# oc delete namespace local-storage

# # Clean up the artifacts from the storage nodes for that resource.
# [[ ! -z $SC ]] && for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/${i} -- chroot /host rm -rfv /mnt/local-storage/${SC}/; done


# Wipe the disks for each of the local volumes listed in step 4 so that they can be reused on each storage node.
oc debug node/<nodename>
chroot /host
DISKS="/dev/disk/by-id/wwn-0x614187705a2c050026a67c4607b3d1cd /dev/disk/by-id/wwn-0x614187705a2c020026a67c1c0546807d /dev/disk/by-id/wwn-0x61866da0577e830026a67beb066415ea"
for disk in $DISKS; do sgdisk --zap-all $disk;done

rm -rfv /etc/lvm/backup/ /etc/lvm/archive/ /dev/loop0 /dev/loop1
rm -rfv /etc/lvm/archive/

rm -rfv /dev/loop0
rm -rfv /dev/loop1

dmsetup remove


# Unlabel the storage nodes.
oc label nodes  --all cluster.ocs.openshift.io/openshift-storage-
oc label nodes  --all topology.rook.io/rack-

oc get nodes -l cluster.ocs.openshift.io/openshift-storage=

# Remove cr instances - may need to clear finalizer if they get stuck
oc delete cephblockpools.ceph.rook.io ocs-storagecluster-cephblockpool
oc delete cephfilesystems.ceph.rook.io ocs-storagecluster-cephfilesystem
oc delete cephclusters.ceph.rook.io ocs-storagecluster-cephcluster

# Remove CustomResourceDefinitions
# [old] oc delete crd backingstores.noobaa.io bucketclasses.noobaa.io cephblockpools.ceph.rook.io cephclusters.ceph.rook.io cephfilesystems.ceph.rook.io cephnfses.ceph.rook.io cephobjectstores.ceph.rook.io cephobjectstoreusers.ceph.rook.io noobaas.noobaa.io ocsinitializations.ocs.openshift.io  storageclusterinitializations.ocs.openshift.io objectbuckets.objectbucket.io objectbucketclaims.objectbucket.io storageclusters.ocs.openshift.io  --wait=true --timeout=5m
oc delete crd backingstores.noobaa.io bucketclasses.noobaa.io cephblockpools.ceph.rook.io cephclients.ceph.rook.io cephclusters.ceph.rook.io cephfilesystems.ceph.rook.io cephnfses.ceph.rook.io cephobjectstores.ceph.rook.io cephobjectstoreusers.ceph.rook.io cephobjectrealms.ceph.rook.io cephobjectzones.ceph.rook.io cephobjectzonegroups.ceph.rook.io cephrbdmirrors.ceph.rook.io noobaas.noobaa.io ocsinitializations.ocs.openshift.io  storageclusterinitializations.ocs.openshift.io objectbuckets.objectbucket.io objectbucketclaims.objectbucket.io storageclusters.ocs.openshift.io  --wait=true --timeout=5m

oc delete -l operators.coreos.com/ocs-operator.openshift-storage
