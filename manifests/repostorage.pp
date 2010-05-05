# manifests/defines.pp

# if you don't like to run a git-daemon for the gitosis daemon
# please set the global variabl $gitosis_daemon to false.

# admins: if set to an emailaddress we will add a email diff hook
# admins_generatepatch: wether to include a patch
# admins_sender: which sender to use
define gitosis::repostorage(
  $ensure = 'present',
  $basedir = 'absent',
  $uid = 'absent',
  $gid = 'uid',
  $password = 'absent',
  $password_crypted = true,
  $admins = 'absent',
  $admins_generatepatch = true,
  $admins_sender = false,
  $initial_admin_pubkey = 'absent',
  $sitename = 'absent',
  $git_vhost = 'absent',
  $gitweb = true
){
  if ($ensure == 'present') and ($initial_admin_pubkey == 'absent') {
    fail("You need to pass \$initial_admin_pubkey if repostorage ${name} should be present!")
  }
  include ::gitosis

  $real_basedir = $basedir ? {
    'absent' => "/home/${name}",
    default => $basedir
  }

  user::managed{"$name":
    ensure => $ensure,
    homedir => $real_basedir,
    uid => $uid,
    gid => $gid,
    password => $password,
    password_crypted => $password_crypted,
  }

  include ::gitosis::gitaccess
  user::groups::manage_user{"manage_${name}_in_group_gitaccess":
    ensure => $ensure,
    user => $name,
    group => $gitaccess,
    require => [ Group['gitaccess'], User::Managed[$name] ],
  }
  if $ensure == 'present' {
    file{"${real_basedir}/initial_admin_pubkey.puppet":
      content => "${initial_admin_pubkey}\n",
      require => User[$name],
      owner => $name, group => $name, mode => 0600;
    }
    exec{"create_gitosis_${name}":
      command => "env -i gitosis-init < initial_admin_pubkey.puppet",
      unless => "test -d ${real_basedir}/repositories",
      cwd => "${real_basedir}",
      user => $name,
      require => [ Package['gitosis'], File["${real_basedir}/initial_admin_pubkey.puppet"] ],
    }

    file{"${real_basedir}/repositories/gitosis-admin.git/hooks/post-update":
      require => Exec["create_gitosis_${name}"],
      owner => $name, group => $name, mode => 0755;
    }

    ::gitosis::emailnotification{"gitosis-admin_${name}":
      gitrepo => "gitosis-admin",
      gitosis_repo => $name,
      basedir => $real_basedir,
      envelopesender => $admins_sender,
      generatepatch => $admins_generatepatch,
      emailprefix => "${name}: gitosis-admin",
      require => File["${real_basedir}/repositories/gitosis-admin.git/hooks/post-update"],
    }
    if $admins != 'absent'  {
      Gitosis::Emailnotification["gitosis-admin_${name}"]{
            mailinglist => $admins,
        }
    } else {
      Gitosis::Emailnotification["gitosis-admin_${name}"]{
        ensure => absent,
        mailinglist => 'root',
      }
    }
  }

  case $gitosis_daemon {
    '': { $gitosis_daemon = true }
  }
  user::groups::manage_user{"manage_gitosisd_in_group_${name}":
    ensure => $ensure,
    user => 'gitosisd',
    group => $name
  }
  case $git_vhost {
    'absent': { $git_vhost_link = '/srv/git' }
    default: {
      include ::gitosis::daemon::vhosts
      $git_vhost_link = "/srv/git/${git_vhost}"
    }
  }
  file{$git_vhost_link: }
  if $gitosis_daemon and $ensure == 'present' {
    include ::gitosis::daemon
    File[$git_vhost_link]{
      ensure => "${real_basedir}/repositories",
    }
    User::Groups::Manage_user["manage_gitosisd_in_group_${name}"]{
      require => [ User['gitosisd'], Group[$name] ],
      notify =>  Service['git-daemon'],
    }
  } else {
    File[$git_vhost_link]{
      ensure => absent,
      force => true,
    }
    if !$gitosis_daemon {
      include ::gitosis::daemon::disable
    }
  }

  case $gitweb_webserver {
    'lighttpd','apache': { $webuser = $gitweb_webserver }
    default: { fail("no supported \$gitweb_webserver defined on ${fqdn}, so can't do git::web::repo: ${name}") }
  }
  if $gitweb and $ensure == 'present' {
    $web_ensure = 'present'
  } else {
    $web_ensure = 'absent'
  }
  user::groups::manage_user{"manage_${webuser}_in_group_${name}":
    ensure => $web_ensure,
    user => $webuser,
    group => $name;
  }

  git::web::repo{$git_vhost: }
  if $web_ensure == 'present' {
    case $git_vhost {
      'absent': { fail("can't do gitweb if \$git_vhost isn't set for ${name} on ${fqdn}") }
      default: {
        if defined(Package[$webuser]){
          User::Groups::Manage_user["manage_${webuser}_in_group_${name}"]{
            require => [ Package[$webuser], Group[$name] ],
          }
        } else {
          User::Groups::Manage_user["manage_${webuser}_in_group_${name}"]{
            require => Group[$name],
          }
        }
        if defined(Service[$webuser]){
          User::Groups::Manage_user["manage_${webuser}_in_group_${name}"]{
            notify => Service[$webuser],
          }
        }
        Git::Web::Repo[$git_vhost]{
          projectroot => "${real_basedir}/repositories",
          projects_list => "${real_basedir}/gitosis/projects.list",
          sitename => $sitename,
        }
      }
    }
  } else {
    Git::Web::Repo[$git_vhost]{
      ensure => 'absent',
    }
  }
}

