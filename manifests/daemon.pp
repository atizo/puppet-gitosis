class gitosis::daemon inherits git::daemon {
  user::managed{'gitosisd':
    name_comment => "gitosis git-daemon",
    managehome => false,
    homedir => '/srv/gitdaemon',
    shell => $operatingsystem ? {
      debian => '/usr/sbin/nologin',
      ubuntu => '/usr/sbin/nologin',
      default => '/sbin/nologin',
    },
  }
  file{'/srv/git-daemon':
    ensure => directory,
    require => User['gitosisd'],
    owner => root, group => gitosisd, mode => 0750;
  } 
  File['/etc/sysconfig/git-daemon']{
    source => [
      "puppet://$server/modules/site-gitosis/sysconfig/$fqdn/git-daemon",
      "puppet://$server/modules/site-gitosis/sysconfig/git-daemon",
      "puppet://$server/modules/gitosis/sysconfig/git-daemon",
    ],
    require +> User['gitosisd'],
  }
}
