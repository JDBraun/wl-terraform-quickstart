resource "azurerm_databricks_workspace" "this" {
  name                                  = "${local.prefix}-workspace"
  resource_group_name                   = azurerm_resource_group.this.name
  location                              = azurerm_resource_group.this.location
  sku                                   = "premium"
  tags                                  = local.tags
  public_network_access_enabled         = true                    //use private endpoint
  network_security_group_rules_required = "NoAzureDatabricksRules" //use private endpoint
  customer_managed_key_enabled          = true
  //infrastructure_encryption_enabled = true
  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = azurerm_virtual_network.this.id
    private_subnet_name                                  = azurerm_subnet.host.name
    public_subnet_name                                   = azurerm_subnet.container.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.host.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.container.id
    storage_account_name                                 = local.dbfsname
  }
  # We need this, otherwise destroy doesn't cleanup things correctly
  depends_on = [
    azurerm_subnet_network_security_group_association.host,
    azurerm_subnet_network_security_group_association.container
  ]
}