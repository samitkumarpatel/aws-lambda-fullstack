# ─────────────────────────────────────────────────────────────
# API GATEWAY + LAMBDA
# ─────────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "datapulse" {
  name        = "datapulse-api"
  description = "DataPulse REST API"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.datapulse.id
  parent_id   = aws_api_gateway_rest_api.datapulse.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.datapulse.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE" # JWT auth handled by Lambda@Edge before request reaches here
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.datapulse.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.datapulse.id
  depends_on  = [aws_api_gateway_integration.lambda]
}

resource "aws_api_gateway_stage" "api" {
  rest_api_id   = aws_api_gateway_rest_api.datapulse.id
  deployment_id = aws_api_gateway_deployment.api.id
  stage_name    = "prod"
}

resource "aws_iam_role" "api_lambda" {
  name = "datapulse-api-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "api_lambda_policy" {
  role = aws_iam_role.api_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        # Emit events to EventBridge when data changes (triggers cache invalidation)
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "api_lambda" {
  type        = "zip"
  output_path = "${path.module}/api_lambda.zip"
  source {
    filename = "index.py"
    content  = <<-EOF
      import boto3
      import json
      import os

      eb = boto3.client('events')

      def handler(event, context):
          method = event.get('httpMethod', 'GET')
          path   = event.get('path', '/')
          tenant = event.get('headers', {}).get('X-Tenant-ID', 'unknown')

          # ... your real business logic here ...

          # On any write operation, emit an event to trigger cache invalidation
          if method in ('POST', 'PUT', 'PATCH', 'DELETE'):
              # Determine which API paths to invalidate based on what changed
              invalidate_paths = determine_invalidation_paths(path)

              eb.put_events(Entries=[{
                  'Source':     'datapulse.api',
                  'DetailType': 'DataChanged',
                  'Detail':     json.dumps({
                      'tenant_id': tenant,
                      'paths':     invalidate_paths,
                      'method':    method,
                      'resource':  path
                  })
              }])

          return {
              'statusCode': 200,
              'headers': {
                  'Content-Type': 'application/json',
                  'Access-Control-Allow-Origin': 'https://datapulse.io'
              },
              'body': json.dumps({'ok': True})
          }

      def determine_invalidation_paths(path):
          # Fine-grained invalidation — only clear what changed
          if '/dashboards' in path:
              return ['/api/dashboards', '/api/dashboards/*']
          elif '/users' in path:
              return ['/api/users', '/api/users/*']
          else:
              return ['/api/*']  # nuclear option for unknown paths
    EOF
  }
}

resource "aws_lambda_function" "api" {
  function_name    = "datapulse-api"
  role             = aws_iam_role.api_lambda.arn
  filename         = data.archive_file.api_lambda.output_path
  source_code_hash = data.archive_file.api_lambda.output_base64sha256
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 29 # API GW times out at 29s
}

resource "aws_lambda_permission" "apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.datapulse.execution_arn}/*/*"
}

# ─────────────────────────────────────────────────────────────
# AUTO CACHE INVALIDATION PIPELINE
#
# Flow:
#   API Lambda writes data
#     → emits DataChanged event to EventBridge
#       → EventBridge triggers Invalidator Lambda
#         → Invalidator calls CloudFront CreateInvalidation API
#           → stale cache cleared within ~60 seconds
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "invalidator" {
  name = "datapulse-invalidator"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "invalidator_policy" {
  role = aws_iam_role.invalidator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = aws_cloudfront_distribution.datapulse.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

data "archive_file" "invalidator" {
  type        = "zip"
  output_path = "${path.module}/invalidator.zip"
  source {
    filename = "index.py"
    content  = <<-EOF
      import boto3
      import json
      import os
      import time

      cf = boto3.client('cloudfront')

      def handler(event, context):
          detail = event.get('detail', {})
          paths  = detail.get('paths', ['/*'])
          tenant = detail.get('tenant_id', 'unknown')

          print(f"Invalidating for tenant={tenant} paths={paths}")

          cf.create_invalidation(
              DistributionId=os.environ['DISTRIBUTION_ID'],
              InvalidationBatch={
                  'Paths': {
                      'Quantity': len(paths),
                      'Items':    paths
                  },
                  # CallerReference must be unique per request
                  'CallerReference': f"{tenant}-{int(time.time())}"
              }
          )
          return {'invalidated': paths}
    EOF
  }
}

resource "aws_lambda_function" "invalidator" {
  function_name    = "datapulse-cache-invalidator"
  role             = aws_iam_role.invalidator.arn
  filename         = data.archive_file.invalidator.output_path
  source_code_hash = data.archive_file.invalidator.output_base64sha256
  handler          = "index.handler"
  runtime          = "python3.12"

  environment {
    variables = {
      DISTRIBUTION_ID = aws_cloudfront_distribution.datapulse.id
    }
  }
}

# EventBridge rule: fire when API Lambda emits DataChanged
resource "aws_cloudwatch_event_rule" "data_changed" {
  name        = "datapulse-data-changed"
  description = "Fires on every data mutation in the DataPulse API"
  event_pattern = jsonencode({
    source      = ["datapulse.api"]
    detail-type = ["DataChanged"]
  })
}

resource "aws_cloudwatch_event_target" "invalidate" {
  rule      = aws_cloudwatch_event_rule.data_changed.name
  target_id = "InvalidateCloudFront"
  arn       = aws_lambda_function.invalidator.arn

  # Pass the paths from the event detail directly to the invalidator
  input_transformer {
    input_paths    = { paths = "$.detail.paths", tenant = "$.detail.tenant_id" }
    input_template = "{\"paths\": <paths>, \"tenant_id\": \"<tenant>\"}"
  }
}

resource "aws_lambda_permission" "eventbridge_invalidator" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.invalidator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.data_changed.arn
}
