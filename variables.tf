variable instances {
  description = "Map of instances names to configuration"
  type        = map
  default     = {
    web = {
      instance_type        = "t2.micro",
    },
    private = {
      user_data        = "t2.nano",
    }
  }
}

