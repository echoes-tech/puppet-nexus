# Class: nexus_artifact
#
# This module downloads Maven Artifacts from Nexus
#
# Parameters:
# [*url*] : The Nexus base url (mandatory)
# [*username*] : The username used to connect to nexus
# [*password*] : The password used to connect to nexus
# [*netrc*] : Use .netrc to connect to nexus
#
# Actions:
# Checks and intialized the Nexus support.
#
# Sample Usage:
#  class nexus {
#   url => http://edge.spree.de/nexus,
#   username => user,
#   password => password
#}
#
class nexus_artifact (
  $ensure = update,
  $url,
  $username = undef,
  $password = undef,
  $netrc = undef,
) {

  # Check arguments
  $nexus_url = $url

  if((!$username and $password) or ($username and !$password)) {
    fail('Cannot initialize the Nexus class - both username and password must be set')
  }

  # Install script
  file { '/opt/nexus-script/nexus_cli.rb':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    source  => 'puppet:///modules/nexus_artifact/nexus_cli.rb',
    require => File['/opt/nexus-script']
  }

  file { '/opt/nexus-script': ensure => directory }

}
