#!/bin/bash

# Default values
DEFAULT_WORKFLOWS_CONTAINER_IMAGE="quay.io/caponetto/orchestrator-workflows:latest"
DEFAULT_GITHUB_TOKEN="notoken"
DEFAULT_WORKFLOWS_RESOURCE_NAME="workflows"
DEFAULT_BACKSTAGE_RESOURCE_NAME="backstage"
DEFAULT_HELM_CHART_CONFIG_YAML="config.yaml"
DEFAULT_JANUS_HELM_CHART_VERSION="2.15.2"

# Required environment variables
if [ -z "$OPENSHIFT_TOKEN" ]; then echo "OPENSHIFT_TOKEN environment variable is not set"; exit 1; fi
if [ -z "$OPENSHIFT_SERVER" ]; then echo "OPENSHIFT_SERVER environment variable is not set"; exit 1; fi
if [ -z "$OPENSHIFT_NAMESPACE" ]; then echo "OPENSHIFT_NAMESPACE environment variable is not set"; exit 1; fi

# Optional environment variables
WORKFLOWS_CONTAINER_IMAGE=${WORKFLOWS_CONTAINER_IMAGE:-$DEFAULT_WORKFLOWS_CONTAINER_IMAGE}
GITHUB_TOKEN=${GITHUB_TOKEN:-$DEFAULT_GITHUB_TOKEN}
WORKFLOWS_RESOURCE_NAME=${WORKFLOWS_RESOURCE_NAME:-$DEFAULT_WORKFLOWS_RESOURCE_NAME}
BACKSTAGE_RESOURCE_NAME=${BACKSTAGE_RESOURCE_NAME:-$DEFAULT_BACKSTAGE_RESOURCE_NAME}
JANUS_HELM_CHART_VERSION=${JANUS_HELM_CHART_VERSION:-$DEFAULT_JANUS_HELM_CHART_VERSION}
HELM_CHART_CONFIG_YAML=${HELM_CHART_CONFIG_YAML:-$DEFAULT_HELM_CHART_CONFIG_YAML}

echo "Logging in to OpenShift cluster"
oc login --token=$OPENSHIFT_TOKEN --server=$OPENSHIFT_SERVER
oc project $OPENSHIFT_NAMESPACE

echo "Cleaning up existing resources"
helm uninstall $BACKSTAGE_RESOURCE_NAME
oc delete all -l app=$WORKFLOWS_RESOURCE_NAME

echo "Creating the deployment for the workflows"
oc new-app $WORKFLOWS_CONTAINER_IMAGE --name=$WORKFLOWS_RESOURCE_NAME
oc create route edge --service=$WORKFLOWS_RESOURCE_NAME
WORKFLOWS_HOST=$(oc get route $WORKFLOWS_RESOURCE_NAME -o jsonpath='{.spec.host}')
WORKFLOWS_ROUTE="https://$WORKFLOWS_HOST"

echo "Adding Helm repositories"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add backstage https://backstage.github.io/charts
helm repo add redhat-developer https://redhat-developer.github.io/rhdh-chart
helm repo update

echo "Creating the deployment for Backstage"
BACKSTAGE_HOST=$(echo $WORKFLOWS_HOST | sed "s/$WORKFLOWS_RESOURCE_NAME/$BACKSTAGE_RESOURCE_NAME/")
BACKSTAGE_ROUTE="https://$BACKSTAGE_HOST"
helm install $BACKSTAGE_RESOURCE_NAME redhat-developer/backstage \
  --version $JANUS_HELM_CHART_VERSION \
  --values $HELM_CHART_CONFIG_YAML \
  --set global.host=$BACKSTAGE_HOST

echo "Configuring additional environment variables"
oc set env deployment/$WORKFLOWS_RESOURCE_NAME \
  KOGITO_SERVICE_URL=$WORKFLOWS_ROUTE \
  ORCHESTRATOR_URL="$BACKSTAGE_ROUTE/api/orchestrator"
oc set env deployment/$BACKSTAGE_RESOURCE_NAME \
  WORKFLOWS_ROUTE=$WORKFLOWS_ROUTE \
  GITHUB_TOKEN=$GITHUB_TOKEN
