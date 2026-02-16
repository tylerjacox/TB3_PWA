import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

export class Tb3Stack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly distribution: cloudfront.Distribution;
  public readonly siteBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // S3 bucket for static PWA files (private — CloudFront OAC only)
    this.siteBucket = new s3.Bucket(this, 'SiteBucket', {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    // CloudFront distribution with OAC, HTTPS redirect, SPA error routing
    this.distribution = new cloudfront.Distribution(this, 'Distribution', {
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.siteBucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        responseHeadersPolicy: this.createResponseHeadersPolicy(),
      },
      defaultRootObject: 'index.html',
      errorResponses: [
        {
          httpStatus: 403,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: cdk.Duration.seconds(0),
        },
        {
          httpStatus: 404,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: cdk.Duration.seconds(0),
        },
      ],
    });

    // Cognito User Pool — email sign-in, self-registration enabled
    this.userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: 'tb3-users',
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      autoVerify: { email: true },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Cognito domain — required for OAuth2 endpoints (authorize, token)
    const userPoolDomain = this.userPool.addDomain('CognitoDomain', {
      cognitoDomain: { domainPrefix: 'tb3-auth' },
    });

    // Google Identity Provider
    const googleSecret = secretsmanager.Secret.fromSecretNameV2(
      this, 'GoogleOAuthSecret', 'tb3/google-oauth',
    );
    const googleProvider = new cognito.UserPoolIdentityProviderGoogle(this, 'GoogleProvider', {
      userPool: this.userPool,
      clientId: googleSecret.secretValueFromJson('clientId').unsafeUnwrap(),
      clientSecretValue: googleSecret.secretValueFromJson('clientSecret'),
      scopes: ['email', 'openid', 'profile'],
      attributeMapping: {
        email: cognito.ProviderAttribute.GOOGLE_EMAIL,
        givenName: cognito.ProviderAttribute.GOOGLE_GIVEN_NAME,
        familyName: cognito.ProviderAttribute.GOOGLE_FAMILY_NAME,
      },
    });

    const callbackUrl = 'https://d1c704j6qnvml9.cloudfront.net/';

    // Cognito App Client — SRP auth + OAuth2 authorization code grant
    this.userPoolClient = this.userPool.addClient('AppClient', {
      authFlows: {
        userSrp: true,
      },
      generateSecret: false,
      preventUserExistenceErrors: true,
      accessTokenValidity: cdk.Duration.hours(24),
      refreshTokenValidity: cdk.Duration.days(30),
      idTokenValidity: cdk.Duration.hours(24),
      oAuth: {
        flows: { authorizationCodeGrant: true },
        scopes: [
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.PROFILE,
        ],
        callbackUrls: [callbackUrl],
        logoutUrls: [callbackUrl],
      },
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.GOOGLE,
        cognito.UserPoolClientIdentityProvider.COGNITO,
      ],
    });

    // Ensure Google provider is created before the client references it
    this.userPoolClient.node.addDependency(googleProvider);

    // Stack outputs
    new cdk.CfnOutput(this, 'BucketName', {
      value: this.siteBucket.bucketName,
      exportName: 'Tb3BucketName',
    });

    new cdk.CfnOutput(this, 'DistributionId', {
      value: this.distribution.distributionId,
      exportName: 'Tb3DistributionId',
    });

    new cdk.CfnOutput(this, 'DistributionUrl', {
      value: `https://${this.distribution.distributionDomainName}`,
      exportName: 'Tb3DistributionUrl',
    });

    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      exportName: 'Tb3UserPoolId',
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: this.userPoolClient.userPoolClientId,
      exportName: 'Tb3UserPoolClientId',
    });

    new cdk.CfnOutput(this, 'CognitoRegion', {
      value: this.region,
      exportName: 'Tb3CognitoRegion',
    });

    new cdk.CfnOutput(this, 'CognitoDomainUrl', {
      value: `https://${userPoolDomain.domainName}.auth.${this.region}.amazoncognito.com`,
      exportName: 'Tb3CognitoDomainUrl',
    });
  }

  private createResponseHeadersPolicy(): cloudfront.ResponseHeadersPolicy {
    return new cloudfront.ResponseHeadersPolicy(this, 'SecurityHeaders', {
      securityHeadersBehavior: {
        contentSecurityPolicy: {
          contentSecurityPolicy: [
            "default-src 'self'",
            "script-src 'self' https://www.gstatic.com https://*.gstatic.com",
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data:",
            `connect-src 'self' https://cognito-idp.${this.region}.amazonaws.com https://*.execute-api.${this.region}.amazonaws.com https://*.auth.${this.region}.amazoncognito.com https://www.gstatic.com https://*.gstatic.com`,
            `form-action 'self' https://*.auth.${this.region}.amazoncognito.com https://accounts.google.com`,
          ].join('; '),
          override: true,
        },
        strictTransportSecurity: {
          accessControlMaxAge: cdk.Duration.days(365),
          includeSubdomains: true,
          override: true,
        },
        contentTypeOptions: { override: true },
        frameOptions: {
          frameOption: cloudfront.HeadersFrameOption.DENY,
          override: true,
        },
        referrerPolicy: {
          referrerPolicy: cloudfront.HeadersReferrerPolicy.SAME_ORIGIN,
          override: true,
        },
      },
    });
  }
}
