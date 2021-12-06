#!/bin/bash
oc delete pod --field-selector=status.phase==Succeeded -n openshift-storage
