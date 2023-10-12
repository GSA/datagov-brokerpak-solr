
.DEFAULT_GOAL := help

DOCKER_OPTS=--rm -v $(PWD):/brokerpak -w /brokerpak
CSB=ghcr.io/gsa/cloud-service-broker:v0.10.0gsa-zip
SECURITY_USER_NAME := $(or $(SECURITY_USER_NAME), user)
SECURITY_USER_PASSWORD := $(or $(SECURITY_USER_PASSWORD), pass)

BROKER_NAME=solr
SERVICE_NAME ?= solr-cloud
PLAN_NAME ?= base
SERVICE_ID ?= 'b9013a91-9ce8-4c18-8035-a135a8cd6ff9'
PLAN_ID ?= 'e35e9675-413f-4f42-83de-ad5003357e77'

# Specify provsion/bind parameters to run a specific example
INSTANCE_NAME ?= instance-$(USER)
CLOUD_PROVISION_PARAMS ?= '{}'
CLOUD_BIND_PARAMS ?= '{}'

# Execute the cloud-service-broker binary inside the running container
CSB_EXEC=docker exec csb-service-$(BROKER_NAME) /bin/cloud-service-broker

# Wait for an instance operation to complete; append with the instance id
# Wait for an binding operation to complete; append with the instance id and binding id
# Fetch the content of a binding; append with the instance id and binding id
CSB_INSTANCE_WAIT=docker exec csb-service-$(BROKER_NAME) ./bin/instance-wait.sh
CSB_BINDING_WAIT=docker exec csb-service-$(BROKER_NAME) ./bin/binding-wait.sh
CSB_BINDING_FETCH=docker exec csb-service-$(BROKER_NAME) ./bin/binding-fetch.sh

PREREQUISITES = docker jq kind kubectl helm
K := $(foreach prereq,$(PREREQUISITES),$(if $(shell which $(prereq)),some string,$(error "Missing prerequisite commands $(prereq)")))


###############################################################################
## General Commands

check:
	@echo CSB_EXEC: $(CSB_EXEC)
	@echo SERVICE_NAME: $(SERVICE_NAME)
	@echo PLAN_NAME: $(PLAN_NAME)
	@echo CLOUD_PROVISION_PARAMS: $(CLOUD_PROVISION_PARAMS)
	@echo CLOUD_BIND_PARAMS: $(CLOUD_BIND_PARAMS)

clean: down ## Bring down the broker service if it's up and clean out the database
	@docker rm -f csb-service-$(BROKER_NAME)
	@rm -f datagov-services-pak-*.brokerpak

# Origin of the subdirectory dependency solution:
# https://stackoverflow.com/questions/14289513/makefile-rule-that-depends-on-all-files-under-a-directory-including-within-subd#comment19860124_14289872
build: manifest.yml solr-on-ecs.yml $(shell find terraform) ## Build the brokerpak(s)
	@docker run --user $(shell id -u):$(shell id -g) $(DOCKER_OPTS) $(CSB) pak build

# Healthcheck solution from https://stackoverflow.com/a/47722899
# (Alpine inclues wget, but not curl.)
up: .env.secrets .env ## Run the broker service with the brokerpak configured. The broker listens on `0.0.0.0:8080`. curl http://127.0.0.1:8080 or visit it in your browser.
	docker run $(DOCKER_OPTS) \
	-p 8080:8080 \
	-e SECURITY_USER_NAME=$(SECURITY_USER_NAME) \
	-e SECURITY_USER_PASSWORD=$(SECURITY_USER_PASSWORD) \
	-e "DB_TYPE=sqlite3" \
	-e "DB_PATH=/tmp/csb-db" \
	-e "GSB_DEBUG=true" \
	--env-file .env \
	--env-file .env.secrets \
	--name csb-service-$(BROKER_NAME) \
	-d --network kind \
	--health-cmd="wget --header=\"X-Broker-API-Version: 2.16\" --no-verbose --tries=1 --spider http://$(SECURITY_USER_NAME):$(SECURITY_USER_PASSWORD)@localhost:8080/v2/catalog || exit 1" \
	--health-interval=2s \
	--health-retries=15 \
	$(CSB) serve
	@while [ "`docker inspect -f {{.State.Health.Status}} csb-service-$(BROKER_NAME)`" != "healthy" ]; do   echo "Waiting for csb-service-$(BROKER_NAME) to be ready..." ;  sleep 2; done
	@echo "csb-service-$(BROKER_NAME) is ready!" ; echo ""
	@docker ps -l

down: ## Bring the cloud-service-broker service down
	-@docker stop csb-service-$(BROKER_NAME)

###############################################################################
## Solr on ECS Commands

.env.secrets:
	@echo Copy .env.secrets-template to .env.secrets, then edit in your own values

ecs-all: clean build up demo-up demo-down down ## Clean and rebuild, run the broker, provision/bind instance, unbind/deprovision instance, and tear the broker down

demo-up: ## Provision a Solr instance on ECS and output the bound credentials
	@( \
	set -e ;\
	echo "Provisioning $(SERVICE_NAME):$(PLAN_NAME):$(INSTANCE_NAME)" ;\
	$(CSB_EXEC) client provision --serviceid $(SERVICE_ID) --planid $(PLAN_ID) --instanceid "$(INSTANCE_NAME)"                     --params '$(CLOUD_PROVISION_PARAMS)';\
	$(CSB_INSTANCE_WAIT) $(INSTANCE_NAME) ;\
	echo "Binding $(SERVICE_NAME):$(PLAN_NAME):$(INSTANCE_NAME):binding" ;\
	$(CSB_EXEC) client bind      --serviceid $(SERVICE_ID) --planid $(PLAN_ID) --instanceid "$(INSTANCE_NAME)" --bindingid binding --params "$(CLOUD_BIND_PARAMS)" | jq -r .response > $(INSTANCE_NAME).binding.json ;\
	)

demo-down: ## Clean up data left over from tests and demos
	@( \
	set -e ;\
	echo "Unbinding and deprovisioning the ${SERVICE_NAME} instance";\
	$(CSB_EXEC) client unbind --bindingid binding --instanceid $(INSTANCE_NAME) --serviceid $(SERVICE_ID) --planid $(PLAN_ID) 2>/dev/null;\
	$(CSB_EXEC) client deprovision --instanceid $(INSTANCE_NAME) --serviceid $(SERVICE_ID) --planid $(PLAN_ID) 2>/dev/null;\
	$(CSB_INSTANCE_WAIT) $(INSTANCE_NAME) ;\
	)

###############################################################################
## SolrCloud on EKS Commands

.env: generate-env.sh
	@echo Generating a .env file containing the k8s config needed by the broker
	@./generate-env.sh

examples.json: examples.json-template
	@./generate-examples.sh > examples.json

kind-up: ## Set up a Kubernetes test environment using KinD
	# Creating a temporary Kubernetes cluster to test against with KinD
	@kind create cluster --config kind/kind-config.yaml --name datagov-broker-test
	# Grant cluster-admin permissions to the `system:serviceaccount:default:default` Service.
	# (This is necessary for the service account to be able to create the cluster-wide
	# Solr CRD definitions.)
	@kubectl create clusterrolebinding default-sa-cluster-admin --clusterrole=cluster-admin --serviceaccount=default:default --namespace=default
	# Install a KinD-flavored ingress controller (to make the Solr instances visible to the host).
	# See (https://kind.sigs.k8s.io/docs/user/ingress/#ingress-nginx for details.
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.1/deploy/static/provider/kind/deploy.yaml
	@kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=270s
	@kubectl apply -f kind/persistent-storage.yml
	# Install the ZooKeeper and Solr operators using Helm
	kubectl create -f https://solr.apache.org/operator/downloads/crds/v0.7.1/all-with-dependencies.yaml
	@helm install --namespace kube-system --repo https://solr.apache.org/charts --version 0.7.1 solr solr-operator

kind-down: ## Tear down the Kubernetes test environment in KinD
	kind delete cluster --name datagov-broker-test
	@rm .env

eks-all: clean build kind-up up demo-up demo-down down kind-down ## Clean and rebuild, start local test environment, run the broker, run the examples, and tear the broker and test env down
.PHONY: all clean build up down test kind-up kind-down demo-up demo-down

# Output documentation for top-level targets
# Thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

