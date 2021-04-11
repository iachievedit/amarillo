Gem::Specification.new do |s|
	s.name    = "yellow"
	s.version = "0.1.0"
	s.summary = "Yellow"
	s.description = "A tool for managing Let's Encrypt dns-01 certificates"
	s.authors     = ["iAchieved.it LLC"]
	s.email       = 'joe@iachieved.it'
	s.files       = ["lib/yellow.rb"]
	s.executables = ["yellow"]
	s.license     = "MIT"
	s.homepage    = "https://github.com/iachievedit/yellow"
	s.add_runtime_dependency "acme-client",     "~> 2.0"
  s.add_runtime_dependency "openssl",         "~> 2.2"
  s.add_runtime_dependency "aws-sdk-core",    "~> 3"
  s.add_runtime_dependency "aws-sdk-route53", "~> 1.48"
end
