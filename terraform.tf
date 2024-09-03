terraform {
  required_providers {
    azurerm = {
      version = "~> 3.63"  # temporariliy constraining the version to 3.x until problems with 4.x are fixed
    }
  }
  required_version = ">=1.5.2"
}

provider "azurerm" {
  features {}
}
