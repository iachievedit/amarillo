#!/usr/bin/env ruby
#
# Inspired by Pete Keen's (pete@petekeen.net) post
# https://www.petekeen.net/lets-encrypt-without-certbot
# 
# Copyright 2021 iAchieved.it LLC
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'logger'          # Logging
require 'acme-client'     # Let's Encrypt
require 'openssl'         # Key Generation
require 'aws-sdk-core'    # Credentials
require 'aws-sdk-route53' # Route 53
require 'resolv'          # DNS Resolvers

class Amarillo

  def initialize(certificatePath, keyPath, awsEnvPath)

    @certificatePath = certificatePath
    @keyPath         = keyPath
    @awsEnvPath      = awsEnvPath

    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO

  end

  def check_dns(domainName, nameservers, value)
    valid = true

    nameservers.each do |nameserver|
      begin
        records = Resolv::DNS.open(nameserver: nameserver) do |dns|
          dns.getresources(
            "_acme-challenge.#{domainName}", 
            Resolv::DNS::Resource::IN::TXT
            )
        end
        records = records.map(&:strings).flatten
        valid = value == records.first
      rescue Resolv::ResolvError
        return false
      end
      return false if !valid
    end

    valid
  end

  def requestCertificate(zone, commonName, email)

    @logger.info "Generating 4096-bit RSA private key"
    key = OpenSSL::PKey::RSA.new(4096)
    client = Acme::Client.new(
      private_key: key, 
      directory: 'https://acme-v02.api.letsencrypt.org/directory'
      )

    account = client.new_account(
      contact: "mailto:#{email}", 
      terms_of_service_agreed: true
      )

    # Generate a certificate order
    @logger.info "Creating certificate order request for #{commonName}"

    order          = client.new_order(identifiers: [commonName])
    authorization  = order.authorizations.first
    label          = "_acme-challenge.#{commonName}"
    record_type    = authorization.dns.record_type
    challengeValue = authorization.dns.record_content

    @logger.info "Challenge value for #{commonName} in #{zone} zone is #{challengeValue}"

    # Update Route 53

    shared_creds = Aws::SharedCredentials.new(path: "#{@awsEnvPath}")
    puts shared_creds.path
    Aws.config.update(credentials: shared_creds)

    # TODO:  Allow the user to set the region
    route53 = Aws::Route53::Client.new(region: 'us-east-2')
    hzone   = route53.list_hosted_zones(max_items: 100)
    .hosted_zones
    .detect { |z| z.name == "#{zone}." }

    change = {
      action: 'UPSERT',
      resource_record_set: {
        name: label,
        type: record_type,
        ttl: 1,
        resource_records: [
          { value: "\"#{challengeValue}\"" }
        ]
      }
    }

    options = {
      hosted_zone_id: hzone.id,
      change_batch: {
        changes: [change]
      }
    }

    route53.change_resource_record_sets(options)

    nameservers = []

    @logger.info "Looking up nameservers for #{zone}"

    Resolv::DNS.open(nameserver: '9.9.9.9') do |dns|
      while nameservers.length == 0
        nameservers = dns.getresources(
          zone,
          Resolv::DNS::Resource::IN::NS
          ).map(&:name).map(&:to_s)
      end
    end

    @logger.info "Waiting for DNS record to propogate"
    while !check_dns(commonName, nameservers, challengeValue)
      sleep 1
    end

    authorization.dns.request_validation

    @logger.info "Requesting validation..."
    authorization.dns.reload
    while authorization.dns.status == 'pending'
    	sleep 2
    	@logger.info "DNS status:  #{authorization.dns.status}"
    	authorization.dns.reload
    end

    @logger.info "Requesting certificate..."

    cert_key = OpenSSL::PKey::RSA.new(4096)
    csr = Acme::Client::CertificateRequest.new(
      private_key: cert_key, 
      names: [commonName]
      )

    order.finalize(csr: csr)

    sleep(1) while order.status == 'processing'

    keyOutputPath =  "#{@keyPath}/#{commonName}.key"
    certOutputPath = "#{@certificatePath}/#{commonName}.crt"

    @logger.info "Saving private key to #{keyOutputPath}"

    File.open(keyOutputPath, "w") do |f|
    	f.puts cert_key.to_pem.to_s
    end

    @logger.info "Saving certificate to #{certOutputPath}"

    File.open(certOutputPath, "w") do |f|
    	f.puts order.certificate
    end

    @logger.info "Cleaning up..."

    change = {
      action: 'DELETE',
      resource_record_set: {
        name: label,
        type: record_type,
        ttl: 1,
        resource_records: [
          { value: "\"#{challengeValue}\"" }
        ]
      }
    }

    options = {
      hosted_zone_id: hzone.id,
      change_batch: {
        changes: [change]
      }
    }

    route53.change_resource_record_sets(options)
  end
end
