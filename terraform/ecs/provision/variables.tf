
##############################
# Solr Leader (and standalone) Configuration
##############################

variable "instance_name" {
  type        = string
  description = "Unique ID to separate solr instanceresources"
}

variable "region" {
  type        = string
  description = "region to create solr ecs cluster"
  default     = "us-west-2"
}

variable "labels" {
  type    = map(any)
  default = {}
}

variable "zone" {
  type        = string
  description = "DNS Zone to host Solr service"
}

variable "solrImageRepo" {
  type        = string
  description = "Repository for the Solr Docker image to use, defaults to docker.io/solr"
  default     = "ghcr.io/gsa/catalog.data.gov.solr"
}

variable "solrImageTag" {
  type        = string
  description = "Tag for the Solr Docker image to use, defaults to 8.6. See https://hub.docker.com/_/solr?tab=tags (or your configured solrImageRepo) for options"
  default     = "8-stunnel-root"
}

variable "solrMem" {
  type        = number
  description = "How much memory to request for each replica (default is '12G')"
  default     = 12288
}

variable "solrCpu" {
  type        = number
  description = "How much vCPU to request for each replica (default is '2048' aka '2 vCPUs')"
  default     = 2048
}

variable "setupLink" {
  type        = string
  description = "The Solr setup file for initialization of cores/authentication/et cetera..."
  default     = "https://raw.githubusercontent.com/GSA/catalog.data.gov/main/solr/solr_setup.sh"
}

##############################
# Solr Follower Configuration
##############################

variable "solrFollowerMem" {
  type        = number
  description = "How much memory to request for each follower replica (default is '12G')"
  default     = 12288
}

variable "solrFollowerCpu" {
  type        = number
  description = "How much vCPU to request for each follower replica (default is '2048' aka '2 vCPUs')"
  default     = 2048
}

variable "solrFollowerCount" {
  type        = number
  description = "How many Solr Followers should be created"
  default     = 0
}

variable "solrFollowerLbWeight" {
  type        = list
  description = "How to distribute traffic load to each follower in percentage"
  default     = [100]
}

variable "solrFollowerDiskSize" {
  type        = number
  description = "How much ephemeral storage disk space Solr Followers will have"
  default     = 50
}

variable "setupFollowerLink" {
  type        = string
  description = "The Solr setup file for Followers to initialize cores/authentication/et cetera..."
  default     = "https://raw.githubusercontent.com/GSA/catalog.data.gov/main/solr/solr_setup.sh"
}

########################
# Solr EFS Configuration
########################

variable "efsProvisionedThroughput" {
  type        = number
  description = "The throughput, measured in MiB/s, that you want to provision for the file system"
  default     = 1
}

variable "efsProvisionedThroughputFollower" {
  type        = number
  description = "The throughput, measured in MiB/s, that you want to provision for the file system (for follower)"
  default     = 1
}

variable "efsPerformanceMode" {
  type        = string
  description = "The file system performance mode. Can be either \"generalPurpose\" or \"maxIO\" (Default: \"generalPurpose\")"
  default     = "generalPurpose"
}

variable "disableEfs" {
  type        = bool
  description = "Launch without EFS volume"
  default     = false
}

variable "disableEfsFollower" {
  type        = bool
  description = "Launch followers without EFS volume"
  default     = false
}

########################
# Solr Alerts Configuration
########################

variable "slackNotification" {
  type        = bool
  description = "The webhook address to receive slack notifications for Solr Errors/restarts"
  default     = false
}

variable "emailNotification" {
  type        = string
  description = "The email address to receive notifications for Solr Errors/restarts"
  default     = ""
}
