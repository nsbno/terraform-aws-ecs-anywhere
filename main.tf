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
    portMappings = [for mapping in var.task_port_mappings : {
      containerPort = mapping.container
      hostPort      = mapping.host
    }]
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

############################################################################################
# Configure Alarm SNS topics for ECS Anywhere
############################################################################################
# Alarm SNS topic for alarms on level DEGRADED.
resource "aws_sns_topic" "degraded_alarms" {
  name = "${var.name_prefix}-ecs-anywhere-degraded-alarms"
  tags = var.tags
}

# Alarm SNS topic for alarms on level CRITICAL
resource "aws_sns_topic" "critical_alarms" {
  name = "${var.name_prefix}-ecs-anywhere-critical-alarms"
  tags = var.tags
}

############################################################################################
# Integrate Cloudwatch Alarms to Pagerduty via SNS topics.
############################################################################################
# Subscribe Critical alarms to PagerDuty
resource "aws_sns_topic_subscription" "critical_alarms_to_pagerduty" {
  count                  = length(var.pager_duty_critical_endpoint) > 0 ? 1 : 0
  endpoint               = var.pager_duty_critical_endpoint
  protocol               = "https"
  endpoint_auto_confirms = true
  topic_arn              = aws_sns_topic.critical_alarms.arn
}

# Subscribe Degraded alarms to PagerDuty
resource "aws_sns_topic_subscription" "degraded_alarms_to_pagerduty" {
  count                  = length(var.pager_duty_degraded_endpoint) > 0 ? 1 : 0
  endpoint               = var.pager_duty_degraded_endpoint
  protocol               = "https"
  endpoint_auto_confirms = true
  topic_arn              = aws_sns_topic.degraded_alarms.arn
}

############################################################################################
# Configure Default Cloudwatch Alarms for service
############################################################################################
resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  metric_name         = "CPUUtilization"
  alarm_name          = "${var.name_prefix}-ecs-anywhere-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.service_alarm_cpu_evaluation_periods
  threshold           = var.service_alarm_cpu_threshold
  namespace           = "AWS/ECS"
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.name_prefix}"
  }
  period            = 60
  statistic         = "Average"
  alarm_description = "${var.name_prefix}-ecs-anywhere has crossed the CPU usage threshold"
  tags              = var.tags
  alarm_actions     = [aws_sns_topic.degraded_alarms.arn]
  ok_actions        = [aws_sns_topic.degraded_alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "high_memory_utilization" {
  metric_name         = "MemoryUtilization"
  alarm_name          = "${var.name_prefix}-ecs-anywhere-memory"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 5
  threshold           = var.service_alarm_memory_threshold
  namespace           = "AWS/ECS"
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.name_prefix}"
  }
  period            = 60
  statistic         = "Average"
  alarm_description = "${var.name_prefix}-ecs-anywhere has crossed the memory usage threshold"
  tags              = var.tags
  alarm_actions     = [aws_sns_topic.degraded_alarms.arn]
  ok_actions        = [aws_sns_topic.degraded_alarms.arn]
}


resource "aws_cloudwatch_metric_alarm" "num_error_logs" {
  metric_name         = "logback.events.count"
  alarm_name          = "${var.name_prefix}-ecs-anywhere-errors-log"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 50
  namespace           = var.name_prefix
  dimensions = {
    level = "error"
  }
  period             = 60
  statistic          = "Sum"
  alarm_description  = "${var.name_prefix}-ecs-anywhere has logged to many errors"
  tags               = var.tags
  alarm_actions      = [aws_sns_topic.degraded_alarms.arn]
  ok_actions         = [aws_sns_topic.degraded_alarms.arn]
  treat_missing_data = "notBreaching"
}

# Lambda subscriptions
resource "aws_cloudwatch_log_subscription_filter" "cloudwatch_access_log_subscription_lambda" {
  count           = var.enable_elasticcloud == false ? 0 : 1
  destination_arn = var.lambda_elasticcloud
  filter_pattern  = ""
  log_group_name  = aws_cloudwatch_log_group.this.name
  name            = "ElasticsearchStream-${var.name_prefix}"
  distribution    = "ByLogStream"
}
