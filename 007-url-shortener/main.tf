# Provider configuration
provider "aws" {
  region = "us-east-1" # Change to your preferred region
}

# Variables
variable "table_name" {
  description = "Name of the DynamoDB table"
  default     = "UrlShortenerTable"
}

variable "custom_domain" {
  description = "Optional custom domain (e.g., short.mydomain.com)"
  default     = ""
}

# DynamoDB Table
resource "aws_dynamodb_table" "url_table" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shortCode"

  attribute {
    name = "shortCode"
    type = "S"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "url_shortener_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_dynamodb_logs_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.url_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function: Shorten URL
data "archive_file" "shorten_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/shorten_lambda.zip"

  source {
    content  = <<EOF
import json
import boto3
import string
import random
import urllib.parse

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${var.table_name}')
chars = string.ascii_letters + string.digits
code_length = 6

def generate_short_code():
    return ''.join(random.choice(chars) for _ in range(code_length))

def handler(event, context):
    body = json.loads(event.get('body', '{}'))
    original_url = body.get('url')
    if not original_url:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'URL is required'})
        }
    if not original_url.startswith(('http://', 'https://')):
        original_url = 'https://' + original_url

    # Ensure URL is valid by parsing
    try:
        parsed = urllib.parse.urlparse(original_url)
        if not parsed.scheme or not parsed.netloc:
            raise ValueError
    except ValueError:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid URL'})
        }

    # Generate unique short code
    for _ in range(3):  # Retry up to 3 times
        short_code = generate_short_code()
        try:
            table.put_item(
                Item={
                    'shortCode': short_code,
                    'originalUrl': original_url
                },
                ConditionExpression='attribute_not_exists(shortCode)'
            )
            domain = event['requestContext']['domainName']
            short_url = f"https://{domain}/{short_code}"
            return {
                'statusCode': 200,
                'body': json.dumps({'shortUrl': short_url})
            }
        except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
            continue

    return {
        'statusCode': 500,
        'body': json.dumps({'error': 'Failed to generate unique short code'})
    }
EOF
    filename = "shorten.py"
  }
}

resource "aws_lambda_function" "shorten_url" {
  function_name = "ShortenUrlFunction"
  handler       = "shorten.handler"
  role          = aws_iam_role.lambda_exec_role.arn
  runtime       = "python3.9"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.shorten_lambda_zip.output_path
  source_code_hash = data.archive_file.shorten_lambda_zip.output_base64sha256
}

# Lambda Function: Redirect URL
data "archive_file" "redirect_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/redirect_lambda.zip"

  source {
    content  = <<EOF
import json
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${var.table_name}')

def handler(event, context):
    short_code = event['pathParameters']['shortCode']
    response = table.get_item(Key={'shortCode': short_code})
    item = response.get('Item')
    if not item:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Short URL not found'})
        }
    return {
        'statusCode': 301,
        'headers': {
            'Location': item['originalUrl']
        },
        'body': ''
    }
EOF
    filename = "redirect.py"
  }
}

resource "aws_lambda_function" "redirect_url" {
  function_name = "RedirectUrlFunction"
  handler       = "redirect.handler"
  role          = aws_iam_role.lambda_exec_role.arn
  runtime       = "python3.9"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.redirect_lambda_zip.output_path
  source_code_hash = data.archive_file.redirect_lambda_zip.output_base64sha256
}

# API Gateway
resource "aws_api_gateway_rest_api" "url_shortener_api" {
  name        = "UrlShortenerApi"
  description = "API for URL shortening service"
}

# API Gateway: /shorten Resource
resource "aws_api_gateway_resource" "shorten_resource" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  parent_id   = aws_api_gateway_rest_api.url_shortener_api.root_resource_id
  path_part   = "shorten"
}

# API Gateway: /{shortCode} Resource
resource "aws_api_gateway_resource" "redirect_resource" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  parent_id   = aws_api_gateway_rest_api.url_shortener_api.root_resource_id
  path_part   = "{shortCode}"
}

# API Gateway: POST /shorten Method
resource "aws_api_gateway_method" "shorten_method" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id   = aws_api_gateway_resource.shorten_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "shorten_integration" {
  rest_api_id             = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id             = aws_api_gateway_resource.shorten_resource.id
  http_method             = aws_api_gateway_method.shorten_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.shorten_url.invoke_arn
}

# API Gateway: GET /{shortCode} Method
resource "aws_api_gateway_method" "redirect_method" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id   = aws_api_gateway_resource.redirect_resource.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.shortCode" = true
  }
}

resource "aws_api_gateway_integration" "redirect_integration" {
  rest_api_id             = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id             = aws_api_gateway_resource.redirect_resource.id
  http_method             = aws_api_gateway_method.redirect_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.redirect_url.invoke_arn
}

# Lambda Permissions for API Gateway
resource "aws_lambda_permission" "shorten_api_permission" {
  statement_id  = "AllowAPIGatewayInvokeShorten"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shorten_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.url_shortener_api.execution_arn}/*/POST/shorten"
}

resource "aws_lambda_permission" "redirect_api_permission" {
  statement_id  = "AllowAPIGatewayInvokeRedirect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redirect_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.url_shortener_api.execution_arn}/*/GET/{shortCode}"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id

  depends_on = [
    aws_api_gateway_integration.shorten_integration,
    aws_api_gateway_integration.redirect_integration
  ]

  stage_name = "prod"
}

# Outputs
output "api_url" {
  description = "The URL of the API Gateway"
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "shorten_url_endpoint" {
  description = "Endpoint to shorten URLs"
  value       = "${aws_api_gateway_deployment.api_deployment.invoke_url}/shorten"
}

output "example_redirect" {
  description = "Example redirect URL format"
  value       = "${aws_api_gateway_deployment.api_deployment.invoke_url}/{shortCode}"
}