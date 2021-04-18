# Yellow

## WARNING
**Development is not complete!**

An Ruby script to issue Let's Encrypt certificates with dns-01 challenges through AWS Route 53.

**NB**:  This documentation is not yet complete!

## Quickstart

Yellow is distributed as a RubyGem and can be installed with:

```
gem install yellow
```

Usage:  `yellow --zone ZONE --name COMMONNAME --email EMAIL`

For example:

```
yellow --zone iachieved.it --name zabbix.operations.iachieved.it --email noreply@iachieved.it
```

## Why?

It's always bothered me that there is an entire industry around making money issuing SSL certificates.  Sure, I understand that OV and EV certificates verify that there's an actual organization behind the certificate and that they are legitimate.  But DV (domain validation) certificates still cost money, and all that's validated is you control a domain or an e-mail address.  Unless you're running a bank...

Enter Let's Encrypt...

Unfortunately there a many of us who want _secure_ communications between services and websites inside a corporate or private network.  Let's Encrypt's out-of-the-box `certbot` assumes that the website is on the public Internet.

## Configuration

To use `yellow` you'll need to provide AWS credentials in an `aws.env` file located in `/etc/yellow/aws.env` or `/usr/local/etc/yellow/`.  These credentials should be that of an AWS IAM user that only has programmatic access to Route 53 with the `AmazonRoute53FullAccess` policy.

The format of the `aws.env` file is:

```
[default]
aws_access_key_id=
aws_secret_access_key=
```

You'll also want to have:

* an E-mail address
* Zone
* Server Name

## Output

By default `yellow` wants to leave files in `/etc/ssl/yellow` and will try to create this directory. 

## Renewals

Let's Encrypt certificates expire 90 days after issuance.

# For Developers

On macOS, without `rvm`

```
sudo gem install bundler
bundle install
```