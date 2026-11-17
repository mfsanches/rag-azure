variable "location" {
  description = "Azure region. Pick one where your chosen models are available."
  type        = string
  default     = "eastus2"
}

variable "name_prefix" {
  description = "Short prefix for resource names (letters and digits)."
  type        = string
  default     = "rag"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.name_prefix))
    error_message = "name_prefix must be 2-8 lowercase letters or digits."
  }
}

variable "resource_group_name" {
  description = "Resource group to create. Defaults to rg-<prefix>-<suffix>."
  type        = string
  default     = null
}

variable "model_deployments" {
  description = "Model deployments. Keys are deployment names used by the app. Capacity is in thousands of tokens per minute."
  type = map(object({
    model    = string
    version  = string
    sku_name = string
    capacity = number
  }))
}

variable "chat_small_deployment" {
  description = "Deployment used for simple questions."
  type        = string
  default     = "chat-small"
}

variable "chat_large_deployment" {
  description = "Deployment used for complex, multi-step questions."
  type        = string
  default     = "chat-large"
}

variable "embedding_deployment" {
  description = "Embedding deployment."
  type        = string
  default     = "embedding"
}

variable "embedding_dimensions" {
  description = "Vector size produced by the embedding model."
  type        = number
  default     = 1536
}

variable "search_sku" {
  description = "AI Search tier. Basic is the lowest tier with private endpoints and semantic ranking."
  type        = string
  default     = "basic"

  validation {
    condition     = contains(["basic", "standard", "standard2"], var.search_sku)
    error_message = "search_sku must be basic, standard or standard2."
  }
}

variable "container_image" {
  description = "Image for the API and ingestion job. The default is a placeholder until you push your own."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "use_created_registry" {
  description = "Pull the image from the registry this configuration creates (set true after pushing to it)."
  type        = bool
  default     = false
}

variable "allowed_ip_addresses" {
  description = "Public IPs allowed to upload documents to storage. Empty = fully private."
  type        = list(string)
  default     = []
}

variable "grant_deployer_upload" {
  description = "Give the identity running Terraform permission to upload documents."
  type        = bool
  default     = true
}

variable "vnet_address_space" {
  description = "Address space of the virtual network."
  type        = string
  default     = "10.20.0.0/16"
}

variable "tags" {
  type = map(string)
  default = {
    workload  = "secure-rag"
    managedBy = "terraform"
  }
}
