# Amarillo

## NB

Development on this application is not yet complete, and `amarillo` should not be used in a production environment at this time.

## Overview

Amarillo is a Ruby application written to automate issuing [Let's Encrypt](https://letsencrypt.org/) certificates using [dns-01 challenges](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) through [Amazon Route 53](https://aws.amazon.com/route53/).

## Installation

Amarillo is distributed as a RubyGem and can be installed with:

```
gem install amarillo
amarillo --init --zone AWS_HOSTED_ZONE --email EMAIL_ADDR
```

If you don't have Ruby installed, you will need to, along with the `ruby-dev` package.

`amarillo` requires the use of OpenSSL libraries and you may need to install with supplying the location of the OpenSSL headers.

macOS:
```
gem install amarillo -- --with-openssl-dir=/opt/homebrew/Cellar/openssl@1.1/1.1.1k
```

Debian/Ubuntu:
```
apt-get install -y ruby-dev libssl-dev
gem install amarillo
```

Usage:  `amarillo --zone ZONE --name COMMONNAME --email EMAIL`

For example:

```
amarillo --zone iachieved.it --name zabbix.operations.iachieved.it --email noreply@iachieved.it
```

## Initialization

To use `amarillo` you'll want to initialize its environment with

```
amarillo --init --zone AWS_HOSTED_ZONE --email EMAIL_ADDR
```

You will need to provide AWS credentials in the `aws.env` file located in `/usr/local/etc/amarillo/aws.env`.  These credentials should be that of an AWS IAM user that only has programmatic access to Route 53 with the `AmazonRoute53FullAccess` policy.

The format of the `aws.env` file is:

```
[default]
aws_access_key_id=
aws_secret_access_key=
```
## Creating a Certificate

Assuming `aws.env` and `config.yml` are configured appropriately:

```
amarillo --name COMMONNAME
```

## Deleting a Certificate

```
amarillo --name COMMONNAME --delete
```

## Listing Certificates

```
amarillo --list
```

## Renewals

Let's Encrypt certificates expire 90 days after issuance.  `amarillo` will renew certificates that are within 30 days of expiration with:

```
amarillo --renew
```

## Output

By default `amarillo` wants to leave files in `/usr/local/etc/ssl/amarillo` and will try to create this directory.  Inside this directory will be:

* `aws.env`
* `config.yml`
* `certificates/`
* `keys/`
* `configs/`

# Referencing a Certificate

`amarillo`, unlike `certbot`, does not edit your webserver configuration files.  You will want to reference the files directly.  

# For Developers

On macOS, without `rvm`

```
sudo gem install bundler
bundle install
```

```
sudo -s ruby -Ilib ./bin/amarillo --zone iachieved.it --name test.iachieved.it --email joe@iachieved.it
```

# Why?

It's always bothered me that there is an entire industry around making money issuing SSL certificates.  Sure, I understand that OV and EV certificates verify that there's an actual organization behind the certificate and that they are legitimate.  But DV (domain validation) certificates still cost money, and all that's validated is you control a domain or an e-mail address.  Unless you're running a bank...

Enter Let's Encrypt...

Unfortunately there a many of us who want _secure_ communications between services and websites inside a corporate or private network.  Let's Encrypt's out-of-the-box `certbot` assumes that the website is on the public Internet.

# Amarillo

Amarillo is the Spanish word for yellow, and is pronounced "ah-ma-ree-show" in honor of mis amigos uruguayos.  🇺🇾🇺🇸  Yellow is also the name of one of my cats.

