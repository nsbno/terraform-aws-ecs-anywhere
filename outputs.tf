output "ecs_service_name" {
  value = aws_ecs_service.this.name
}

output "task_execution_role" {
  value = aws_iam_role.task_execution.name
}

output "task_role" {
  value = aws_iam_role.task.name
}

output "critical_alarm_topic_arn" {
  value = aws_sns_topic.critical_alarms.arn
}

output "degraded_alarm_topic_arn" {
  value = aws_sns_topic.degraded_alarms.arn
}