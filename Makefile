
.DEFAULT_GOAL := help

DOCKER_OPTS=--rm -v $(PWD):/brokerpak -w /brokerpak #--network=host
CSB=cfplatformeng/csb
SECURITY_USER_NAME := $(or $(SECURITY_USER_NAME), user)
SECURITY_USER_PASSWORD := $(or $(SECURITY_USER_PASSWORD), pass)

EDEN_EXEC=eden --client user --client-secret pass --url http://127.0.0.1:8080
OPERATOR_PROVISION_PARAMS=$(shell cat examples.json |jq '.[] | select(.service_name | contains("solr-operator")) | .provision_params')
OPERATOR_BIND_PARAMS=$(shell cat examples.json |jq '.[] | select(.service_name | contains("solr-operator")) | .bind_params')
CLOUD_PROVISION_PARAMS=$(shell cat examples.json |jq '.[] | select(.service_name | contains("solr-cloud")) | .provision_params')
CLOUD_BIND_PARAMS=$(shell cat examples.json |jq '.[] | select(.service_name | contains("solr-cloud")) | .bind_params')

clean: cleanup ## Bring down the broker service if it's up, clean out the database, and remove created images
	docker-compose down -v --remove-orphans --rmi local

# Origin of the subdirectory dependency solution: 
# https://stackoverflow.com/questions/14289513/makefile-rule-that-depends-on-all-files-under-a-directory-including-within-subd#comment19860124_14289872
build: manifest.yml $(shell find services) ## Build the brokerpak(s)
	@docker run $(DOCKER_OPTS) $(CSB) pak build

# Healthcheck solution from https://stackoverflow.com/a/47722899 
# (Alpine inclues wget, but not curl.)
up: ## Run the broker service with the brokerpak configured. The broker listens on `0.0.0.0:8080`. curl http://127.0.0.1:8080 or visit it in your browser. 
	docker run $(DOCKER_OPTS) \
	-p 8080:8080 \
	-e SECURITY_USER_NAME=$(SECURITY_USER_NAME) \
	-e SECURITY_USER_PASSWORD=$(SECURITY_USER_PASSWORD) \
	-e "DB_TYPE=sqlite3" \
	-e "DB_PATH=/tmp/csb-db" \
	--name csb-service \
	-d --network kind \
	--health-cmd="wget --header=\"X-Broker-API-Version: 2.16\" --no-verbose --tries=1 --spider http://$(SECURITY_USER_NAME):$(SECURITY_USER_PASSWORD)@localhost:8080/v2/catalog || exit 1" \
	--health-interval=2s \
	--health-retries=15 \
	$(CSB) serve
	@while [ "`docker inspect -f {{.State.Health.Status}} csb-service`" != "healthy" ]; do   echo "Waiting for csb-service to be ready..." ;  sleep 2; done
	@echo "csb-service is ready!" ; echo ""
	@docker ps -l

down: ## Bring the cloud-service-broker service down
	docker rm -f csb-service

# Normally we would run 
	# $(CSB) client run-examples --filename examples.json
# ...to test the brokerpak. However, some of our examples need to run nested.
# So, we'll run them manually with eden via "demo" and "cleanup" targets.
test: examples.json demo-up demo-down ## Execute the brokerpak examples against the running broker
	@echo "Running examples..."

demo-up: examples.json ## Provision a SolrCloud instance and output the bound credentials
	# Provision and bind a solr-operator service
	$(EDEN_EXEC) provision -i operatorinstance -s solr-operator  -p base -P '$(OPERATOR_PROVISION_PARAMS)'
	$(EDEN_EXEC) bind -b operatorbinding -i operatorinstance
	$(EDEN_EXEC) credentials -b operatorbinding -i operatorinstance

	# Provision and bind a solr-cloud instance (using credentials from the
	# operator instance)
	$(EDEN_EXEC) provision -i cloudinstance -s solr-cloud  -p base -P '$(CLOUD_PROVISION_PARAMS)'
	$(EDEN_EXEC) bind -b cloudbinding -i cloudinstance
	$(EDEN_EXEC) credentials -b cloudbinding -i cloudinstance
	
demo-down: examples.json ## Clean up data left over from tests and demos
	# Unbind and deprovision the solr-cloud instance
	-$(EDEN_EXEC) unbind -b cloudbinding -i cloudinstance
	-$(EDEN_EXEC) deprovision -i cloudinstance

	# Unbind and deprovision the solr-operator instance
	-$(EDEN_EXEC) unbind -b operatorbinding -i operatorinstance
	-$(EDEN_EXEC) deprovision -i operatorinstance
	-rm examples.json 2>/dev/null; true

	# Remove any orphan services
	rm ~/.eden/config  2>/dev/null ; true
	helm uninstall solr 2>/dev/null ; true
	helm uninstall zookeeper 2>/dev/null ; true
	kubectl delete role solrcloud-access-read-only 2>/dev/null ; true
	helm uninstall example 2>/dev/null ; true
	kubectl delete role solrcloud-access-all 2>/dev/null ; true
	kubectl delete secret basic-auth1 2>/dev/null ; true
	kubectl delete role zookeeper-zookeeper-operator 2>/dev/null ; true

test-env-up: ## Set up a Kubernetes test environment using KinD
	# Creating a temporary Kubernetes cluster to test against with KinD
	@kind create cluster --config kind-config.yaml --name datagov-broker-test
	# Granting cluster-admin permissions to the `system:serviceaccount:default:default` Service.
	# (This is necessary for the service account to be able to create the cluster-wide
	# Solr CRD definitions.)
	@kubectl create clusterrolebinding default-sa-cluster-admin --clusterrole=cluster-admin --serviceaccount=default:default --namespace=default
	# Installing a KinD-flavored ingress controller (to make the Solr instances visible to the host)
	# See (https://kind.sigs.k8s.io/docs/user/ingress/#ingress-nginx for details
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
	@kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=90s

test-env-down: ## Tear down the Kubernetes test environment in KinD
	kind delete cluster --name datagov-broker-test

all: clean build up wait test down ## Clean and rebuild, then bring up the server, run the examples, and bring the system down
.PHONY: all clean build up down wait test demo-up demo-down test-env-up test-env-down

examples.json:
	./generate-examples.sh > examples.json

# Output documentation for top-level targets
# Thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help 
help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

