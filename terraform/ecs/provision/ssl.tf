
locals {
  domain          = "solr-${local.lb_name}.${var.zone}"
  leader_domain   = "leader.${local.domain}"
  follower_domain = "follower.${local.domain}"
}

# Create ACM certificate for the sub-domain
resource "aws_acm_certificate" "cert" {
  domain_name               = local.domain
  subject_alternative_names = ["*.${local.domain}"]

  validation_method = "DNS"
  tags = merge(var.labels, {
    environment = var.instance_name
  })
}

# Validate the certificate using DNS method (Parent Domain and subdomains)
resource "aws_route53_record" "cert_validation" {
  name    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_type
  zone_id = aws_route53_zone.cluster.id
  records = [tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

resource "time_sleep" "cert_validate" {
  depends_on = [
    aws_acm_certificate.cert,
    aws_acm_certificate_validation.cert,
    aws_route53_record.cert_validation
  ]

  create_duration = "15s"
}
