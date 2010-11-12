#
# if you don't like to run a git-daemon at all, please
# set the global variable $gitosis_gitdaemon to false.
#
# admins: if set to an emailaddress we will add a email diff hook
# admins_generatepatch: wether to include a patch
# admins_sender: which sender to use
#
define gitosis::repostore(
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
  $gitdaemon = true,
  $vhost = false,
  $gitweb = true,
  $gitweb_sitename = 'absent'
){
  require gitosis
  if $ensure == 'present' and $initial_admin_pubkey == 'absent' {
    fail "You need to pass \$initial_admin_pubkey for a gitosis repostorage"
  }
  $real_basedir = $basedir ? {
    'absent' => "/srv/git/$name",
    default => $basedir,
  }
  user::managed{$name:
    ensure => $ensure,
    homedir => $real_basedir,
    uid => $uid,
    gid => $gid,
    password => $password,
    password_crypted => $password_crypted,
  }
  user::groups::manage_member{"manage_${name}_in_group_gitaccess":
    ensure => $ensure,
    user => $name,
    group => 'gitaccess',
    require => [
      User::Managed[$name],
      Group['gitaccess'],
    ],
  }
  if $ensure == 'present' {
    file{"$real_basedir/initial_admin_pubkey.puppet":
      content => "$initial_admin_pubkey\n",
      require => User::Managed[$name],
      owner => $name, group => $name, mode => 0600;
    }
    exec{"create_gitosis_repostore_$name":
      user => $name,
      cwd => $real_basedir,
      command => "env -i gitosis-init < initial_admin_pubkey.puppet",
      unless => "test -d $real_basedir/repositories",
      require => [
        Package['gitosis'],
        File["$real_basedir/initial_admin_pubkey.puppet"],
      ],
    }
    file{"$real_basedir/repositories/gitosis-admin.git/hooks/post-update":
      require => Exec["create_gitosis_repostore_$name"],
      owner => $name, group => $name, mode => 0755;
    }
    gitosis::emailnotification{"gitosis-admin_$name":
      repository => "gitosis-admin",
      repostore => $name,
      repostore_basedir => $real_basedir,
      envelopesender => $admins_sender,
      generatepatch => $admins_generatepatch,
      emailprefix => "$name: gitosis-admin",
      require => File["$real_basedir/repositories/gitosis-admin.git/hooks/post-update"],
    }
    if $admins != 'absent' {
      Gitosis::Emailnotification["gitosis-admin_$name"]{
        mailinglist => $admins,
      }
    } else {
      Gitosis::Emailnotification["gitosis-admin_$name"]{
        ensure => absent,
        mailinglist => 'root',
      }
    }
  }

  # git-daemon
  if $gitosis_gitdaemon == '' {
    $gitosis_gitdaemon = true
    include gitosis::daemon
  } elsif $gitosis_gitdaemon {
    include gitosis::daemon
  } else {
    include gitosis::daemon::disable
  }
  user::groups::manage_member{"manage_gitosisd_in_group_$name":
    group => $name,
    user => 'gitosisd',
  }
  if $vhost {
    $gitvhost_link = "/srv/git-daemon/$vhost"
    file{$gitvhost_link: }
  }
  if $gitosis_gitdaemon and $gitdaemon and ($ensure == 'present') {
    if $vhost {
      File[$gitvhost_link]{
        ensure => "$real_basedir/repositories",
      }
    }
    User::Groups::Manage_member["manage_gitosisd_in_group_$name"]{
      ensure => present,
      require => [
        User['gitosisd'],
        User::Managed[$name],
      ],
      notify => Service['git-daemon'],
    }
  } else {
    User::Groups::Manage_member["manage_gitosisd_in_group_$name"]{
      ensure => absent,
    }
    if $vhost {
      File[$gitvhost_link]{
        ensure => absent,
        force => true,
      }
    }
  }

  # gitweb
  if $gitweb and $ensure == 'present' {
    $web_ensure = 'present'
  } else {
    $web_ensure = 'absent'
  }
  user::groups::manage_member{"manage_${gitweb_webserver}_in_group_${name}":
    ensure => $web_ensure,
    user => $gitweb_webserver,
    group => $name;
  }
  if $vhost {
    git::web::repo{$vhost: }
  }
  if $web_ensure == 'present' {
    if ! $vhost {
      fail("can't do gitweb if \$vhost isn't set for $name on $fqdn")
    }
    if defined(Package[$gitweb_webserver]){
      User::Groups::Manage_member["manage_${gitweb_webserver}_in_group_${name}"]{
        require => [
          Package[$gitweb_webserver],
          User::Managed[$name],
        ],
      }
    } else {
      User::Groups::Manage_member["manage_${gitweb_webserver}_in_group_${name}"]{
        require => User::Managed[$name],
      }
    }
    if defined(Service[$gitweb_webserver]){
      User::Groups::Manage_member["manage_${gitweb_webserver}_in_group_${name}"]{
        notify => Service[$gitweb_webserver],
      }
    }
    Git::Web::Repo[$vhost]{
      projectroot => "$real_basedir/repositories",
      projects_list => "$real_basedir/gitosis/projects.list",
      sitename => $gitweb_sitename,
    }
  } else {
    if $vhost {
      Git::Web::Repo[$vhost]{
        ensure => 'absent',
      }
    }
  }
}
