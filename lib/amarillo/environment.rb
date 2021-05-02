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

require 'logger'
require 'yaml'
require 'aws-sdk-core'

DefaultAmarilloHome = "/usr/local/etc/amarillo/"

class Amarillo::Environment

  attr_reader :certificatePath, :keyPath, :configPath, :configsPath, :config, :awsEnvFile

  def initialize(amarilloHome:  DefaultAmarilloHome)

    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO

    @amarilloHome    = amarilloHome
    @certificatePath = amarilloHome + "/certificates"
    @keyPath         = amarilloHome + "/keys"
    @configPath      = amarilloHome
    @configsPath     = amarilloHome + "/configs"
    @configFile      = amarilloHome + "/config.yml"
    @awsEnvFile      = amarilloHome + "/aws.env"

  end

  # Public method to create default configuration files
  def init(zone = nil, email = nil)

    unless File.exist?(@configsPath) and File.directory?(@configsPath)
      begin
        @logger.info "Creating #{@configsPath} directory"
        FileUtils.mkpath(@configsPath)
      rescue
        @logger.error("Cannot create #{@configsPath} directory")
        return false
      end
    end

    unless File.exist?(@certificatePath) and File.directory?(@certificatePath)
      begin
        @logger.info "Creating #{@certificatePath} directory"
        FileUtils.mkpath(@certificatePath)
      rescue
        @logger.error("Cannot create #{@certificatePath} directory")
        return false
      end 
    end 

    unless File.exist?(@keyPath) and File.directory?(@keyPath)
      begin
        @logger.info "Creating #{@keyPath} directory"
        FileUtils.mkpath(@keyPath)
      rescue
        @logger.error("Cannot create #{@keyPath} directory")
        return false
      end 
    end

    # Create aws.env
    unless File.exist?(@awsEnvFile) then
      awsEnv = <<-HEREDOC
[default]
aws_access_key_id = 
aws_secret_access_key = 
HEREDOC
      @logger.info("Creating blank #{@awsEnvFile}")
      @logger.warn("NOTE:  aws_access_key_id and aws_secret_access_key must be specified in this file.")
      File.write(@awsEnvFile, awsEnv)
    else
      @logger.info("Refusing to overwrite #{@awsEnvFile}")
    end

    # Create config.yml
    unless File.exist?(@configFile) then
      @logger.info("Creating default configuration #{@configFile}")
      config = {
        "defaults" => {
          "region"      =>  'us-east-2',
          "profile"     => 'default',
          "email"       =>  email,
          "zone"        =>  zone,
          "nameservers" =>  ['208.67.222.222', '9.9.9.9'],
          "key_type"    =>  'ec,secp384r1'
      }}
      File.write(@configFile, config.to_yaml)
    else
      @logger.info("Refusing to overwrite #{@configFile}")
    end

    # Create RSA private key for Let's Encrypt account
    privateKeyPath = "#{@keyPath}/letsencrypt.key"

    unless File.exist? privateKeyPath then
      @logger.info "Generating 4096-bit RSA private key for Let's Encrypt account"

      privateKey = OpenSSL::PKey::RSA.new(4096)


      File.open(privateKeyPath, "w") do |f|
        f.puts privateKey.to_pem.to_s
      end
      File.chmod(0400, privateKeyPath)
    end
  end

  #
  # Verify paths exist and are writable
  # Verify aws.env exists and is formatted correctly
  # Verify config.yml exists and is formatted correctly
  #
  def verify
    @logger.info "Verifying amarillo environment"
    if not verify_env()    then return false end
    if not verify_awsenv() then return false end
    if not verify_config() then return false end
    return true
  end

  def verify_env
    unless File.stat(@certificatePath).writable? then
      @logger.error(@certificatePath + " is not writable")
      return false
    end

    unless File.stat(@keyPath).writable? then
      @logger.error(@keyPath + " is not writable")
      return false
    end 

    return true
  end

  def verify_awsenv()
    awsEnvFile = Pathname.new(@awsEnvFile)
    if not awsEnvFile.exist? then 
      @logger.error("#{awsEnvFile} does not exist")
      return false 
    end           

    awsCredentials = Aws::SharedCredentials.new(path: "#{@awsEnvFile}")

    if awsCredentials.credentials.access_key_id.length != 20 then
      @logger.error("#{@awsEnvFile} aws_access_key_id does not appear to be valid")
      return false
    end

    if awsCredentials.credentials.secret_access_key.length != 40 then
      @logger.error("#{@awsEnvFile} aws_secret_access_key does not appear to be valid")
      return false
    end

    return true
  end

  def verify_config()
    if not File.exist?(@configFile) then
      @logger.error("#{@configFile} does not exist")
      return false
    end

    begin
      YAML.load(File.read(@configFile))
    rescue
      @logger.error("Unable to load configuration file")
      return false
    end 

    return true
  end

  def load_config()
    if verify_config() then
      @config = YAML.load(File.read(@configFile))
    end
  end

  def get_zone_nameservers

    self.load_config

    nameservers      = @config["defaults"]["nameservers"]
    zone             = @config["defaults"]["zone"]

    @logger.info "Looking up nameservers for #{zone}"

    zone_nameservers = []
    Resolv::DNS.open(nameserver:  nameservers) do |dns|
      while zone_nameservers.length == 0
        zone_nameservers = dns.getresources(
          zone,
          Resolv::DNS::Resource::IN::NS
          ).map(&:name).map(&:to_s)
      end
    end

    @logger.info "Found #{zone_nameservers.length} nameservers for zone #{zone}:  #{zone_nameservers}"

    return zone_nameservers
  end 

end
