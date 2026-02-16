#!/bin/bash
set -euo pipefail

# Load stack outputs from CloudFormation
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name Tb3Stack \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

DIST_ID=$(aws cloudformation describe-stacks \
  --stack-name Tb3Stack \
  --query 'Stacks[0].Outputs[?OutputKey==`DistributionId`].OutputValue' \
  --output text)

POOL_ID=$(aws cloudformation describe-stacks \
  --stack-name Tb3Stack \
  --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
  --output text)

CLIENT_ID=$(aws cloudformation describe-stacks \
  --stack-name Tb3Stack \
  --query 'Stacks[0].Outputs[?OutputKey==`UserPoolClientId`].OutputValue' \
  --output text)

API_URL=$(aws cloudformation describe-stacks \
  --stack-name Tb3ApiStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
  --output text)

COGNITO_DOMAIN=$(aws cloudformation describe-stacks \
  --stack-name Tb3Stack \
  --query 'Stacks[0].Outputs[?OutputKey==`CognitoDomainUrl`].OutputValue' \
  --output text)

REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-us-west-2}}

echo "Deploying to bucket: $BUCKET"
echo "CloudFront distribution: $DIST_ID"

# Generate .env.production from stack outputs
echo "Generating app/.env.production from CloudFormation outputs..."
cat > app/.env.production <<EOF
VITE_COGNITO_USER_POOL_ID=$POOL_ID
VITE_COGNITO_CLIENT_ID=$CLIENT_ID
VITE_COGNITO_REGION=$REGION
VITE_API_URL=$API_URL
VITE_COGNITO_DOMAIN=$COGNITO_DOMAIN
EOF

# Build PWA
echo "Building PWA..."
cd app && npm run build && cd ..

# Sync hashed assets with immutable cache headers
echo "Uploading assets..."
aws s3 sync app/dist "s3://$BUCKET" --delete \
  --cache-control "max-age=31536000,immutable" \
  --exclude "index.html" \
  --exclude "sw.js" \
  --exclude "manifest.webmanifest"

# Upload Cast receiver (outside Vite build, always revalidate)
if [ -f app/cast-receiver/index.html ]; then
  aws s3 cp app/cast-receiver/index.html "s3://$BUCKET/cast-receiver/index.html" \
    --cache-control "max-age=0,must-revalidate" \
    --content-type "text/html"
fi
if [ -f app/cast-receiver/receiver.js ]; then
  aws s3 cp app/cast-receiver/receiver.js "s3://$BUCKET/cast-receiver/receiver.js" \
    --cache-control "max-age=0,must-revalidate" \
    --content-type "application/javascript"
fi

# Upload non-cacheable files (always revalidate)
aws s3 cp app/dist/index.html "s3://$BUCKET/index.html" \
  --cache-control "max-age=0,must-revalidate"

aws s3 cp app/dist/sw.js "s3://$BUCKET/sw.js" \
  --cache-control "max-age=0,must-revalidate"

if [ -f app/dist/manifest.webmanifest ]; then
  aws s3 cp app/dist/manifest.webmanifest "s3://$BUCKET/manifest.webmanifest" \
    --cache-control "max-age=0,must-revalidate"
fi

# Invalidate CloudFront for non-cached files
echo "Invalidating CloudFront..."
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "/index.html" "/sw.js" "/manifest.webmanifest" "/cast-receiver/index.html" "/cast-receiver/receiver.js"

echo ""
echo "Deploy complete!"

SITE_URL=$(aws cloudformation describe-stacks \
  --stack-name Tb3Stack \
  --query 'Stacks[0].Outputs[?OutputKey==`DistributionUrl`].OutputValue' \
  --output text)

echo "Site: $SITE_URL"
