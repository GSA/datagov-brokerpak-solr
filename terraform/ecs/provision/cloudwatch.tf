
resource "aws_sns_topic" "solr_memory_updates" {
  name = "solr-${local.lb_name}-memory-topic"
}

resource "aws_lambda_permission" "solr_restarts_with_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.solr_restarts.arn
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.solr_memory_updates.arn
}

resource "aws_cloudwatch_metric_alarm" "solr-leader-oom" {
  alarm_name          = "Solr-${local.lb_name}-MemoryThreshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "MemoryUtilized"
  statistic           = "Average"
  period              = "600"
  threshold           = "25000"
  datapoints_to_alarm = "1"
  alarm_description   = "This metric monitors solr memory consumption"

  dimensions = {
    ClusterName = aws_ecs_cluster.solr-cluster.name
    ServiceName = aws_ecs_service.solr.name
  }

  alarm_actions             = [aws_sns_topic.solr_memory_updates.arn]
  ok_actions                = [aws_sns_topic.solr_memory_updates.arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "solr-follower-oom" {
  count               = var.solrFollowerCount
  alarm_name          = "Solr-${local.lb_name}-Follower-${count.index}-MemoryThreshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "MemoryUtilized"
  statistic           = "Average"
  period              = "600"
  threshold           = "25000"
  datapoints_to_alarm = "1"
  alarm_description   = "This metric monitors solr memory consumption"

  dimensions = {
    ClusterName = aws_ecs_cluster.solr-cluster.name
    ServiceName = aws_ecs_service.solr-follower[count.index].name
  }

  alarm_actions             = [aws_sns_topic.solr_memory_updates.arn]
  ok_actions                = [aws_sns_topic.solr_memory_updates.arn]
  insufficient_data_actions = []
}
