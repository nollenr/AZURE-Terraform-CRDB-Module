terraform {
  required_providers {
    azurerm = {
      version = ">=3.63.0"
    }
  }
  required_version = ">=1.5.2"
}

provider "azurerm" {
  features {}
}
