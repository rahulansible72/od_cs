#!/bin/bash

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

get_storagecluster () {
  OCSCLUSTER_NAME=$(oc get StorageCluster --no-headers)
  OCSTATUS=$?
  [ $OCSTATUS -eq 0 ] && { ask "OCS Cluster: ${OCSCLUSTER_NAME} is present, continue?" N || exit 2; }
}

get_cluster_params () {
  export CLUSTER_UUID=$(oc get clusterversions.config.openshift.io version -o jsonpath='{.spec.clusterID}{"\n"}')
  export INFRA_ID=$(oc get infrastructures.config.openshift.io cluster -o jsonpath='{.status.infrastructureName}{"\n"}')
  export API_URL=$(oc get infrastructures.config.openshift.io cluster -o jsonpath='{.status.apiServerURL}{"\n"}')
  export INFRA_NAME=$(awk -F/ '{n=split($3, a, "."); printf("%s", a[n-5])}' <<< $API_URL)
  export AWS_REGION=$(oc get machines -n openshift-machine-api --no-headers | awk '{print $4}' | head -n 1)
  export AWS_AZS=$(oc get machines -n openshift-machine-api --no-headers | awk '{print $5}' | sort | uniq)
  export AWS_NUM_AZS=4
  export AWS_AMI=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')
  export AWS_ACCESS_KEY_ID=$(oc get secret aws-creds -n kube-system -o jsonpath='{.data.aws_access_key_id}' | base64 -d)
  export AWS_SECRET_ACCESS_KEY=$(oc get secret aws-creds -n kube-system -o jsonpath='{.data.aws_secret_access_key}' | base64 -d)
  #show_cluster_params
}

show_cluster_params () {
  echo "Cluster UUID: $CLUSTER_UUID"
  echo "Cluster Infrastructure ID: $INFRA_ID"
  echo "Cluster Canonical Name: $INFRA_NAME"
  echo "Cluster AWS Region: $AWS_REGION"
  echo "Cluster AWS Availability Zones: $AWS_AZS"
  echo "There are $AWS_NUM_AZS availability zones being used in this region."
  echo "AWS Machine AMI: $AWS_AMI"
}

install_ns_op () {
    echo
    echo "Setting up Project/Namespace..."
    oc apply -f 1.1_storage_namespace.yaml
    oc project openshift-storage
    echo
    echo "Adding Operator Group and Installing Operator..."
    oc apply -f 1.2_opgrp_and_operator.yaml
    #echo
    #echo "Enabling Cluster Monitoring..."

    #oc label --overwrite=true namespace openshift-storage "openshift.io/cluster-monitoring=true"
}

label_infra_nodes () {
  OCS_1A_NODES=$(oc get nodes --selector=topology.kubernetes.io/zone=us-east-1a,cluster.ocs.openshift.io/openshift-storage --no-headers | awk '{print $1}')
  OCS_1B_NODES=$(oc get nodes --selector=topology.kubernetes.io/zone=us-east-1b,cluster.ocs.openshift.io/openshift-storage --no-headers | awk '{print $1}')
  OCS_1C_NODES=$(oc get nodes --selector=topology.kubernetes.io/zone=us-east-1c,cluster.ocs.openshift.io/openshift-storage --no-headers | awk '{print $1}')
  OCS_1D_NODES=$(oc get nodes --selector=topology.kubernetes.io/zone=us-east-1d,cluster.ocs.openshift.io/openshift-storage --no-headers | awk '{print $1}')

}

setup_compute () {
  echo "Patching Machine AutoScaler for Compute MachineSets"
  oc patch -n openshift-machine-api machineautoscaler compute-1a --type json -p='[{ "op": "replace", "path": "/spec/minReplicas", "value": 1 }]'
  oc patch -n openshift-machine-api machineautoscaler compute-1b --type json -p='[{ "op": "replace", "path": "/spec/minReplicas", "value": 1 }]'
  oc patch -n openshift-machine-api machineautoscaler compute-1c --type json -p='[{ "op": "replace", "path": "/spec/minReplicas", "value": 1 }]'
  oc patch -n openshift-machine-api machineautoscaler compute-1d --type json -p='[{ "op": "replace", "path": "/spec/minReplicas", "value": 1 }]'

  echo "Scaling Compute MachineSets"
  oc scale --replicas=1 machineset compute-1a -n openshift-machine-api
  oc scale --replicas=1 machineset compute-1b -n openshift-machine-api
  oc scale --replicas=1 machineset compute-1c -n openshift-machine-api
  oc scale --replicas=1 machineset compute-1d -n openshift-machine-api

  #echo "Waiting for Machine Deployments..."
  if ask "Ready to continue? (after machines and nodes are deployed and ready)" Y; then
    OCS_1A_NODE=$(oc get nodes --selector=machine.openshift.io/cluster-api-machineset=compute-1a --no-headers | awk '{print $1}')
    echo "Zone 1A: $OCS_1A_NODE"
    OCS_1B_NODE=$(oc get nodes --selector=machine.openshift.io/cluster-api-machineset=compute-1b --no-headers | awk '{print $1}')
    echo "Zone 1B: $OCS_1B_NODE"
    OCS_1C_NODE=$(oc get nodes --selector=machine.openshift.io/cluster-api-machineset=compute-1c --no-headers | awk '{print $1}')
    echo "Zone 1C: $OCS_1C_NODE"
    OCS_1D_NODE=$(oc get nodes --selector=machine.openshift.io/cluster-api-machineset=compute-1d --no-headers | awk '{print $1}')
    echo "Zone 1D: $OCS_1D_NODE"

    oc label node ${OCS_1A_NODE} node-role.kubernetes.io/infra="" cluster.ocs.openshift.io/openshift-storage=""
    oc label node ${OCS_1B_NODE} node-role.kubernetes.io/infra="" cluster.ocs.openshift.io/openshift-storage=""
    oc label node ${OCS_1C_NODE} node-role.kubernetes.io/infra="" cluster.ocs.openshift.io/openshift-storage=""
    oc label node ${OCS_1D_NODE} node-role.kubernetes.io/infra="" cluster.ocs.openshift.io/openshift-storage=""

#  echo "- Setting up machineset..."
#  helm_machineset
  fi

}



helm_machineset () {
#  echo "Setting up secret for machineset creation"
#  envsubst < machineset-temp-aws-secret.yaml > temp-ms-secret.yaml
#  oc apply -n openshift-machine-api -f temp-ms-secret.yaml
  echo
  echo "Setting up new machines..."
  for az in $AWS_AZS; do
    if [ -f "values-$az.yaml" ]; then
      echo "values-$az.yaml already exists, overwriting..."
    fi
    az=$az envsubst < machineset-values-template.yaml > values-$az.yaml
    echo "Generating Machineset for AZ: $az"
    # helm template ocs-ms machineset/ -f values-$az.yaml > final-$az.yaml
    helm upgrade -i ocs-ms-$az machineset/ -f values-$az.yaml
  done
}
# helm upgrade -i
#echo oc apply -f - -n openshift-machine-api

echo "Discover OCS 4.6 Cluster Deployment"
echo "-----------------------------------"
echo
#echo "Checking for current oc login session..."

#OCUSER=$(oc whoami)
#  OCSTATUS=$?
#  [ $OCSTATUS -eq 0 ] && echo "- User: ${OCUSER} is logged in." || { echo "- Error, Not logged in."; exit 1; }




echo
echo "Checking for current OCS install..."
oc project openshift-storage 2>/dev/null
  OCSTATUS=$?
  if [ $OCSTATUS -eq 0 ]
  then
    echo "- openshift-storage project already exists."
    OCSCLUSTER_NAME=$(oc get StorageCluster --no-headers| awk '{print $1}')
    OCSTATUS=$?
    [ $OCSTATUS -eq 0 ] && { echo "OCS Cluster: ${OCSCLUSTER_NAME} is present."; }
    #[ $OCSTATUS -eq 0 ] && { echo "OCS Cluster: ${OCSCLUSTER_NAME} is present."; exit 2; }
  else
    echo "- No openshift-storage project."
  fi

get_cluster_params

#echo
#echo "Current OCP (non-master) nodes:"
#oc get nodes --no-headers | grep -v master | awk '{print "- " $1 "\t" $3 }' | sort -k2 -V

#echo
#echo "Currently utilized zones:"
#oc get machines --no-headers -n openshift-machine-api | awk '{print "- " $5}' | sort | uniq

echo
#if ask "Create OCS project/namespace and install operator? (No will exit)" Y; then
  echo "- Setting up NS and Operator..."
  install_ns_op
#else
#  exit
#fi

echo
#if ask "[Helm] Deploy machineset and build machines?" Y; then
#  echo "- Setting up machineset..."
#  helm_machineset
#else
#  echo "- Skipping machineset creation."
#  if ask "Label/taint existing infra nodes?" N; then
#    label_infra_nodes
#  fi
#  echo "    Infra Nodes Labelled."
  echo "- Spinning Up Compute nodes..."
  setup_compute
#fi

echo
if ask "Deploy storage cluster?" Y; then
#  if ask "Enable cluster-wide encryption?" Y; then
    export CLUSTER_MANIFEST="3.2e_storage_cluster_enc.yaml"
#  else
#    export CLUSTER_MANIFEST="3.2_storage_cluster.yaml"
#  fi
  echo "- Installing storage cluster..."
  oc apply -f $CLUSTER_MANIFEST -n openshift-storage
#else
#  "- Skipping storage cluster installation."
fi

echo
echo "- [Waiting for Cluster Deployment]"
#pause for 2.5mins
sleep 150
echo
echo "- Deploying Tools Pod"
oc patch OCSInitialization ocsinit -n openshift-storage --type json --patch '[{ "op": "replace", "path": "/spec/enableCephTools", "value": true }]'

echo
if ask "Patch replicas to 4? (wait for cluster deployment to complete)" Y; then
  echo "- Patching Replicas to 4..."
  oc patch -n openshift-storage storagecluster ocs-storagecluster --type json -p='[{ "op": "replace", "path": "/spec/storageDeviceSets/0/replica", "value": 4 }]'
  sleep 30s
fi

echo
if ask "Deploy RGW? (wait for previous ops to complete)" Y; then
  echo "- Deploying Ceph Object Storage (RADOS Gateways)..."
  oc apply -f 4.1_rgw_deploy.yaml
  echo "- Setting up Route to Ceph Object Storage (RADOS Gateways)..."
  oc apply -f 4.2_rgw_route.yaml
  echo "- Setting up Ceph Object StorageClass..."
  oc apply -f 4.3_rgw_storageclass.yaml
fi

echo
#noobaa mcg
echo "- Scaling down MCG Operator..."
oc scale deployment noobaa-operator --replicas 0
echo "- Configuring MCG Default Backing Store to Ceph RBD..."
oc apply -f 3.5-noobaa-backingstore.yaml
echo "- Scaling down MCG Operator..."
oc scale deployment noobaa-operator --replicas 1
echo "- Setting MCG to Managed..."
oc patch -n openshift-storage storagecluster ocs-storagecluster --type json -p='[{ "op": "replace", "path": "/spec/multiCloudGateway/reconcileStrategy", "value": "manage" }]'
sleep 20
echo "- Re-applying Backing Store Configuration..."
oc apply -f 3.5-noobaa-backingstore.yaml
echo "[NooBaa MCG should be available in ~10mins]"

