
// Wait on Credential Due to Race Condition - Other solutions could be applied
// https://kb.databricks.com/en_US/terraform/failed-credential-validation-checks-error-with-terraform 
resource "null_resource" "previous" {}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [null_resource.previous]

  create_duration = "30s"
}

// Credential Configuration
resource "databricks_mws_credentials" "this" {
  account_id       = var.databricks_account_id
  role_arn         = var.cross_account_role_arn
  credentials_name = "${var.resource_prefix}-credentials"
  depends_on = [time_sleep.wait_30_seconds]
}

// Storage Configuration
resource "databricks_mws_storage_configurations" "this" {
  account_id                 = var.databricks_account_id
  bucket_name                = var.bucket_name
  storage_configuration_name = "${var.resource_prefix}-storage"
}

// Backend REST VPC Endpoint Configuration
resource "databricks_mws_vpc_endpoint" "backend_rest" {
  account_id          = var.databricks_account_id
  aws_vpc_endpoint_id = var.backend_rest
  vpc_endpoint_name   = "${var.resource_prefix}-vpce-backend-${var.vpc_id}"
  region              = var.region
}

// Backend Rest VPC Endpoint Configuration
resource "databricks_mws_vpc_endpoint" "backend_relay" {
  account_id          = var.databricks_account_id
  aws_vpc_endpoint_id = var.backend_relay
  vpc_endpoint_name   = "${var.resource_prefix}-vpce-relay-${var.vpc_id}"
  region              = var.region
}

// Network Configuration
resource "databricks_mws_networks" "this" {
  account_id         = var.databricks_account_id
  network_name       = "${var.resource_prefix}-network"
  security_group_ids = var.security_group_ids
  subnet_ids         = var.subnet_ids
  vpc_id             = var.vpc_id
  vpc_endpoints {
    dataplane_relay = [databricks_mws_vpc_endpoint.backend_relay.vpc_endpoint_id]
    rest_api        = [databricks_mws_vpc_endpoint.backend_rest.vpc_endpoint_id]
  }
}

// Private Access Setting Configuration
resource "databricks_mws_private_access_settings" "pas" {
  account_id                   = var.databricks_account_id
  private_access_settings_name = "${var.resource_prefix}-PAS"
  region                       = var.region
  public_access_enabled        = true
  private_access_level         = "ACCOUNT"
}

// Workspace Configuration
resource "databricks_mws_workspaces" "this" {
  account_id      = var.databricks_account_id
  aws_region      = var.region
  workspace_name  = var.resource_prefix
  credentials_id                           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id                 = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id                               = databricks_mws_networks.this.network_id
  private_access_settings_id               = databricks_mws_private_access_settings.pas.private_access_settings_id
  pricing_tier                             = "ENTERPRISE"
  depends_on                               = [databricks_mws_networks.this]
  external_customer_info {
    customer_name = var.customer_name 
    authoritative_user_email = var.authoritative_user_email
    authoritative_user_full_name = var.authoritative_user_full_name
  }
}