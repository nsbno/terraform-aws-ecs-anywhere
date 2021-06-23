data "aws_region" "this" {}

locals {
  current_region = data.aws_region.this.name
}

resource "aws_cloudwatch_log_group" "this" {
  name              = var.name_prefix
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "logs_to_task" {
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.logs_for_task.json
}

locals {
  task_environment = [
    for k, v in var.task_container_environment : {
      name  = k
      value = v
    }
  ]

  task_secrets = [
    for k, v in var.task_container_secrets : {
      name      = k
      valueFrom = v
    }
  ]

  container_definitions = jsonencode([{
    name      = var.container_name != "" ? var.container_name : var.name_prefix
    image     = var.task_container_image
    essential = true
    logConfiguration = {
      "logDriver" : "awslogs",
      "options" : {
        "awslogs-group" : aws_cloudwatch_log_group.this.name,
        "awslogs-region" : local.current_region,
        "awslogs-stream-prefix" : "container"
      }
    }
    command     = var.task_container_command
    healthCheck = var.task_container_health_check
    environment = local.task_environment
    secrets     = local.task_secrets
  }])
}

resource "aws_ecs_task_definition" "task" {
  family                   = var.name_prefix
  execution_role_arn       = aws_iam_role.task_execution.arn
  network_mode             = "bridge"
  requires_compatibilities = ["EXTERNAL"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = local.container_definitions
  dynamic "placement_constraints" {
    for_each = var.task_placement_constraints
    content {
      type       = placement_constraints.value.type
      expression = placement_constraints.value.expression
    }
  }
  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name                               = var.name_prefix
  cluster                            = var.cluster_arn
  task_definition                    = aws_ecs_task_definition.task.arn
  desired_count                      = var.desired_count
  launch_type                        = "EXTERNAL"
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  wait_for_steady_state              = var.wait_for_steady_state
  deployment_controller {
    type = var.deployment_controller_type
  }
  tags = var.tags
}
