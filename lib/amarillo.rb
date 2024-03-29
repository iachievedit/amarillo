#!/usr/bin/env ruby
#
# Inspired by Pete Keen's (pete@petekeen.net) post
# https://www.petekeen.net/lets-encrypt-without-certbot
# 
# Copyright 2022 iAchieved.it LLC
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
require 'yaml'            # YAML
require 'terminal-table'  # Tablular output

class Amarillo

  def initialize(amarilloHome)

    @environment = Amarillo::Environment.new(amarilloHome:  amarilloHome)

    if not @environment.verify then raise "Cannot initialize amarillo" end

    @environment.load_config

    @certificatePath = @environment.certificatePath
    @keyPath         = @environment.keyPath
    @config          = @environment.config
    @awsEnvFile      = @environment.awsEnvFile
    @configsPath     = @environment.configsPath

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

  def get_route53
    shared_creds = Aws::SharedCredentials.new(path: "#{@awsEnvFile}")

    Aws.config.update(credentials: shared_creds)

    region  = @config["defaults"]["region"] ? @config["defaults"]["region"] : 'us-east-2'
    @route53 = Aws::Route53::Client.new(region: region)
    @hzone   = @route53.list_hosted_zones(max_items: 100).hosted_zones.detect { |z| z.name == "#{@zone}." }

  end

  def requestCertificate(configPath:  nil, certConfig:  nil)

    if configPath
      certConfig = YAML.load(File.read(configPath))
    end
    
    commonName     = certConfig["commonName"]
    email          = certConfig["email"]
    zone           = certConfig["zone"]
    key_type       = certConfig["key_type"]
    renewal_action = certConfig["renewal_action"]

    @zone = zone

    acmeUrl = @config["defaults"]["acme_url"] ? @config["defaults"]["acme_url"] : 'https://acme-v02.api.letsencrypt.org/directory'

    # Load private key

    @logger.info "Loading 4096-bit RSA private key for Let's Encrypt account"
    @logger.info "Let's Encrypt directory set to #{acmeUrl}"

    key = OpenSSL::PKey::RSA.new File.read "#{@keyPath}/letsencrypt.key"

    client = Acme::Client.new private_key: key, 
                              directory:   acmeUrl

    account = client.new_account contact: "mailto:#{email}", 
                                 terms_of_service_agreed: true

    # Generate a certificate order
    @logger.info "Creating certificate order request for #{commonName}"

    order          = client.new_order(identifiers: [commonName])
    authorization  = order.authorizations.first
    label          = "_acme-challenge.#{commonName}"
    record_type    = authorization.dns.record_type
    challengeValue = authorization.dns.record_content

    @logger.info "Challenge value for #{commonName} in #{zone} zone is #{challengeValue}"

    self.get_route53

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
      hosted_zone_id: @hzone.id,
      change_batch: {
        changes: [change]
      }
    }

    @route53.change_resource_record_sets(options)

    at_exit do 
      self.cleanup label, record_type, challengeValue
    end


    nameservers = @environment.get_zone_nameservers

    @logger.info "Waiting for DNS record to propagate"
    while !check_dns(commonName, nameservers, challengeValue)
      sleep 5
      @logger.info "Still waiting..."
    end

    authorization.dns.request_validation

    @logger.info "Requesting validation..."
    authorization.dns.reload
    while authorization.dns.status == 'pending'
    	sleep 5
    	@logger.info "DNS status:  #{authorization.dns.status}"
    	authorization.dns.reload
    end

    @logger.info "Generating key"

    # Create certificate yml
    #certConfig = {
    #  "commonName"  =>  commonName,
    #  "email"       =>  email,
    #  "zone"        =>  zone,
    #  "renewal_action" => renewal_action,
    #}

    if key_type
      certConfig["key_type"] = key_type
    else
      key_type = @config["defaults"]["key_type"]
      certConfig["key_type"] = key_type
    end 

    type, args = key_type.split(',')

    if type == 'ec' then
      certPrivateKey = OpenSSL::PKey::EC.new(args).generate_key
    elsif type == 'rsa' then
      if args.to_i > 0
        certPrivateKey = OpenSSL::PKey::RSA.new(args.to_i)
      else
        @logger.error("Invalid RSA key size:  #{args}")
      end 
    end

    @logger.info "Requesting certificate..."  
    csr = Acme::Client::CertificateRequest.new private_key: certPrivateKey, 
                                               names: [commonName]

    while order.status != 'ready'
      sleep(1)
      @logger.info "Order status:  #{order.status}"
      order.reload
      raise if order.status == 'invalid'
    end

    @logger.info "Order status:  #{order.status}"

    begin                                               
      order.finalize(csr: csr)
    rescue
      @logger.error("Error finalizing certificate order")
      raise 
    end

    keyOutputPath =  "#{@keyPath}/#{commonName}.key"
    certOutputPath = "#{@certificatePath}/#{commonName}.crt"

    @logger.info "Saving private key to #{keyOutputPath}"

    File.open(keyOutputPath, "w") do |f|
    	f.puts certPrivateKey.to_pem.to_s
    end

    keyMode = @config["defaults"]["key_mode"] || 0600
    if keyMode
      File.chmod(keyMode, keyOutputPath)
    else
      File.chmod(0600, keyOutputPath)
    end

    @logger.info "Saving certificate to #{certOutputPath}"

    File.open(certOutputPath, "w") do |f|
    	f.puts order.certificate
    end

    owner = certConfig["owner"] || @config["defaults"]["owner"] || "root"
    group = certConfig["group"] || @config["defaults"]["group"] || "root"
    begin
      FileUtils.chown(owner, group, keyOutputPath)
    rescue
      @logger.info "Unable to change ownership of key file #{keyOutputPath}"
    end

    certConfigFile = "#{@configsPath}/#{commonName}.yml"

    @logger.info "Saving certificate configuration to #{certConfigFile}"
    File.write(certConfigFile, certConfig.to_yaml)

    self.doRenewalAction renewal_action

  end

  def cleanup(label, record_type, challengeValue)
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
      hosted_zone_id: @hzone.id,
      change_batch: {
        changes: [change]
      }
    }

    @route53.change_resource_record_sets(options)
  end

  def listCertificates

    rows = []

    Dir["#{@configsPath}/*.yml"].each do |c|
      config = YAML.load(File.read(c))

      cn = config["commonName"]

      certificatePath = "#{@certificatePath}/#{cn}.crt"
      raw = File.read certificatePath
      certificate = OpenSSL::X509::Certificate.new raw      

      rows <<  [config["commonName"], config["email"],
                config["zone"], config["key_type"], certificate.not_after]

    end

    t = Terminal::Table.new :headings => ['commonName','email','zone','keytype','expiration'], :rows => rows
    puts t
  end

  def deleteCertificate(commonName)
    @logger.info "Deleting certificate #{commonName}"

    certConfigFile = @configsPath + "/#{commonName}.yml"
    certificatePath = @certificatePath + "/#{commonName}.crt"
    keyPath         = @keyPath         + "/#{commonName}.key"

    `rm -f #{certConfigFile} #{certificatePath} #{keyPath}`

  end

  # Renew all certificates
  def renewCertificates
    t = Time.now
    @logger.info "Renewing certificates"

    Dir["#{@configsPath}/*.yml"].each do |c|
      config = YAML.load(File.read(c))

      cn = config["commonName"]

      certificatePath = "#{@certificatePath}/#{cn}.crt"
      raw = File.read certificatePath
      certificate = OpenSSL::X509::Certificate.new raw      
      daysToExpiration = (certificate.not_after - t).to_i / (24 * 60 * 60)

      if daysToExpiration < 30 then
        @logger.info "#{cn} certificate needs to be renewed"
        self.requestCertificate configPath:  c
      else
        @logger.info "#{cn} certificate does not need to be renewed"
      end
    end
  end

  # Renew specific certificate, implied force
  def renewCertificate(commonName)

    configPath = "#{@configsPath}/#{commonName}.yml"
    self.requestCertificate configPath:  configPath

  end

  def doRenewalAction(renewal_action)

    if renewal_action

        @logger.info "Executing certificate renewal action:  #{renewal_action}"

        begin
          %x( #{renewal_action} )
          @logger.info "Renewal action returned:  #{$?}"
        rescue
          @logger.error("Error executing certificate renewal action")
          raise
        end 

    end

  end

end


require 'amarillo/environment'
