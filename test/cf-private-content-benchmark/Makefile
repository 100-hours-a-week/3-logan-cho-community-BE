SHELL := /bin/bash
ROOT := $(CURDIR)
TF_DIR := $(ROOT)/terraform
CONFIG ?= ./configs/benchmark.config.json
REMOTE_DIR ?= ~/cf-private-content-benchmark
REMOTE_HOST ?=

.PHONY: init plan apply destroy ssh run-local run-remote fetch-results summarize

init:
	cd $(TF_DIR) && terraform init

plan:
	cd $(TF_DIR) && terraform plan -var-file=terraform.tfvars

apply:
	cd $(TF_DIR) && terraform apply -var-file=terraform.tfvars

destroy:
	cd $(TF_DIR) && terraform destroy -var-file=terraform.tfvars

ssh:
	bash -lc "$$(cd $(TF_DIR) && terraform output -raw ssh_command)"

run-local:
	npm install
	node scripts/run-local-benchmark.js --config "$(CONFIG)"

run-remote:
	@if [[ -z "$(REMOTE_HOST)" ]]; then echo "REMOTE_HOST is required, e.g. azureuser@<vm_public_ip>"; exit 1; fi
	ssh "$(REMOTE_HOST)" "mkdir -p $(REMOTE_DIR)"
	scp -r "$(ROOT)/." "$(REMOTE_HOST):$(REMOTE_DIR)/"
	ssh "$(REMOTE_HOST)" "cd $(REMOTE_DIR) && npm install && node scripts/run-remote-benchmark.js --config $(CONFIG)"

fetch-results:
	@if [[ -z "$(REMOTE_HOST)" ]]; then echo "REMOTE_HOST is required, e.g. azureuser@<vm_public_ip>"; exit 1; fi
	bash scripts/collect-results.sh "$(REMOTE_HOST)" "$(REMOTE_DIR)"

summarize:
	npm install
	node scripts/summarize-results.js --raw-dir "$(ROOT)/results/raw" --summary-dir "$(ROOT)/results/summary"
