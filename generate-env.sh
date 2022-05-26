#!/bin/bash

set -e

# Generate terraform.tfvars needed for mucking about directly with terraform/provision
cat > terraform/standalone_ecs/provision/terraform.tfvars << HEREDOC
zone          = "ssb-dev.data.gov"
solrImageRepo = "ghcr.io/gsa/catalog.data.gov.solr"
solrImageTag  = "8-stunnel-root"
instance_name = "example"
solrCpu       = 2048
solrMem       = 12288
HEREDOC

# Use the same terraform.tfvars config for mucking about directly with terraform/bind.
cp terraform/standalone_ecs/provision/terraform.tfvars terraform/standalone_ecs/bind/terraform.tfvars
