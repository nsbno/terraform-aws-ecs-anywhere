variable "name_prefix" {
  description = "A prefix used for naming resources."
  type        = string
}

variable "container_name" {
  description = "Optional name to use for the for the container. (`var.name_prefix` is used by default.)"
  default     = ""
  type        = string
}

variable "cluster_arn" {
  description = "The ARN of the ECS cluster to create the ECS service in."
  type        = string
}

variable "task_placement_constraints" {
  description = "A list of placement constraints to apply to the ECS task."
  default     = []
}

variable "task_container_image" {
  description = "The image used to start a container."
  type        = string
}

variable "desired_count" {
  description = "The number of instances of the task definitions to place and keep running."
  default     = 1
  type        = number
}

variable "task_cpu" {
  description = "Amount of CPU to reserve for the task."
  default     = null
  type        = number
}

variable "task_memory" {
  description = "The soft limit (in MiB) of memory to reserve for the container."
  default     = 512
  type        = number
}


variable "task_container_command" {
  description = "The command that is passed to the container."
  default     = []
  type        = list(string)
}

variable "task_container_environment" {
  description = "The environment variables to pass to a container."
  default     = {}
  type        = map(string)
}

variable "task_container_secrets" {
  description = "The secret variables from Parameter Store or Secrets Manager to pass to a container."
  default     = {}
  type        = map(string)
}

variable "log_retention_in_days" {
  description = "Number of days the logs will be retained in CloudWatch."
  default     = 30
  type        = number
}

# https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_HealthCheck.html
variable "task_container_health_check" {
  description = "An object representing a container health check."
  default     = null
  type        = any
}

variable "deployment_minimum_healthy_percent" {
  default     = 50
  description = "The lower limit of the number of running tasks that must remain running and healthy in a service during a deployment."
  type        = number
}

variable "deployment_maximum_percent" {
  default     = 200
  description = "The upper limit of the number of running tasks that can be running in a service during a deployment."
  type        = number
}

variable "deployment_controller_type" {
  default     = "ECS"
  type        = string
  description = "Type of deployment controller. Valid values: CODE_DEPLOY, ECS, EXTERNAL."
}

variable "wait_for_steady_state" {
  default     = false
  description = "Whether to wait for the ECS service to reach a steady state."
  type        = bool
}

variable "tags" {
  description = "A map of tags (key-value pairs) passed to resources."
  type        = map(string)
  default     = {}
}
