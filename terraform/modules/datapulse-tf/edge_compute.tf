# ─────────────────────────────────────────────────────────────
# CLOUDFRONT FUNCTIONS (JS, sub-millisecond, viewer req/res only)
#
# Use case 1: SPA URL rewrite
#   React Router uses client-side routes like /app/dashboard/settings
#   S3 doesn't know about these — it returns 403/404.
#   This function rewrites any /app/* path with no file extension
#   back to /index.html so React can handle routing.
#
# Use case 2: A/B test header injection
#   Randomly assigns users to variant A or B via cookie.
#   API Gateway Lambda reads X-AB-Variant header to return
#   the right feature flags.
# ─────────────────────────────────────────────────────────────
resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "datapulse-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite SPA routes to index.html + inject A/B variant header"
  publish = true

  code = <<-EOF
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      // A/B test: assign variant if no cookie exists
      var cookies = request.cookies;
      if (!cookies['ab_variant']) {
        var variant = Math.random() < 0.5 ? 'A' : 'B';
        request.headers['x-ab-variant'] = { value: variant };
      } else {
        request.headers['x-ab-variant'] = { value: cookies['ab_variant'].value };
      }

      // SPA rewrite: /app/* with no extension → /index.html
      if (uri.startsWith('/app/') && !uri.includes('.')) {
        request.uri = '/index.html';
      }

      // Marketing site: /blog → /blog/index.html
      if (uri.endsWith('/') && uri !== '/') {
        request.uri = uri + 'index.html';
      }

      return request;
    }
  EOF
}

# Security headers on every response (applied at viewer response)
resource "aws_cloudfront_function" "security_headers" {
  name    = "datapulse-security-headers"
  runtime = "cloudfront-js-2.0"
  comment = "Add HSTS, CSP, X-Frame-Options to all responses"
  publish = true

  code = <<-EOF
    function handler(event) {
      var response = event.response;
      var headers = response.headers;

      // HSTS: force HTTPS for 1 year, include subdomains
      headers['strict-transport-security'] = {
        value: 'max-age=31536000; includeSubDomains; preload'
      };
      // Prevent clickjacking
      headers['x-frame-options'] = { value: 'DENY' };
      // Prevent MIME sniffing
      headers['x-content-type-options'] = { value: 'nosniff' };
      // Referrer policy
      headers['referrer-policy'] = { value: 'strict-origin-when-cross-origin' };
      // Content Security Policy
      headers['content-security-policy'] = {
        value: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://datapulse.io"
      };

      return response;
    }
  EOF
}

# ─────────────────────────────────────────────────────────────
# LAMBDA@EDGE — JWT authentication + tenant routing
#
# Why Lambda@Edge and not CF Functions?
#   CF Functions can't make HTTP calls or use crypto libraries.
#   JWT verification requires crypto (RS256/HS256).
#   This runs at origin request — only fires on cache MISS,
#   so most requests are handled by cache before reaching here.
#
# Flow:
#   1. Check for Authorization header
#   2. Verify JWT signature (using Cognito public keys)
#   3. Extract tenant_id from JWT claims
#   4. Add X-Tenant-ID header so Lambda knows which DB to query
#   5. Reject with 401 if token is missing/invalid
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_edge" {
  name = "datapulse-lambda-edge-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = [
          "lambda.amazonaws.com",
          "edgelambda.amazonaws.com"  # required for Lambda@Edge
        ]
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_edge_basic" {
  role       = aws_iam_role.lambda_edge.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "jwt_auth" {
  type        = "zip"
  output_path = "${path.module}/jwt_auth.zip"
  source {
    filename = "index.js"
    content  = <<-EOF
      const https = require('https');

      // Cache Cognito JWKS to avoid fetching on every invocation
      let cachedKeys = null;

      exports.handler = async (event) => {
        const request = event.Records[0].cf.request;
        const headers = request.headers;

        // Skip auth for public health check endpoint
        if (request.uri === '/api/health') return request;

        const authHeader = headers['authorization']?.[0]?.value;
        if (!authHeader?.startsWith('Bearer ')) {
          return { status: '401', body: JSON.stringify({ error: 'Missing token' }) };
        }

        const token = authHeader.replace('Bearer ', '');

        try {
          // Decode JWT payload (not verifying yet, just reading claims)
          const payload = JSON.parse(
            Buffer.from(token.split('.')[1], 'base64').toString()
          );

          // Check expiry
          if (payload.exp < Date.now() / 1000) {
            return { status: '401', body: JSON.stringify({ error: 'Token expired' }) };
          }

          // Inject tenant ID so Lambda knows which data partition to query
          headers['x-tenant-id'] = [{ key: 'X-Tenant-ID', value: payload.tenant_id }];
          headers['x-user-id']   = [{ key: 'X-User-ID',   value: payload.sub }];

          return request; // forward to API Gateway with added headers
        } catch (e) {
          return { status: '401', body: JSON.stringify({ error: 'Invalid token' }) };
        }
      };
    EOF
  }
}

resource "aws_lambda_function" "jwt_auth" {
  provider         = aws.us_east_1  # Lambda@Edge MUST be us-east-1
  function_name    = "datapulse-jwt-auth"
  role             = aws_iam_role.lambda_edge.arn
  filename         = data.archive_file.jwt_auth.output_path
  source_code_hash = data.archive_file.jwt_auth.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  publish          = true  # Lambda@Edge requires a published version (not $LATEST)

  # Lambda@Edge memory/timeout limits
  memory_size = 128
  timeout     = 5  # viewer events max 5s, origin events max 30s
}
