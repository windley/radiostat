#!/usr/bin/perl -w
# First, start the daemon.
#   ./thermometer.pl
# Then you may run the test with
#   echo "ping" | netcat localhost 5422
#   kill $(cat /tmp/net.pid)
# Don't forget to check /var/log/messages!

use warnings;
use strict;

use lib qw(../Kinetic);

use Log::Report;
use Any::Daemon;
use Getopt::Long     qw/GetOptions :config no_ignore_case bundling/;
use LWP::UserAgent;
use MIME::Lite;
use MIME::Base64;
use Getopt::Std;
use JSON;


use Kinetic::Raise;



#
## get command-line options
#

my $mode     = 0;     # increase output

my %os_opts  =
  ( pid_file   => "/tmp/temperature.pid",  # usually in /var/run
    user       => undef,
    group      => undef
  );

my %run_opts =
  ( background => 1,
    max_childs => 1,    # there can only be one multiplexer
    sleep_secs => 60,
  );

GetOptions
   'background|bg!' => \$run_opts{background},
   'childs|c=i'     => \$run_opts{max_childs},
   'group|g=s'      => \$os_opts{group},
   'pid-file|p=s'   => \$os_opts{pid_file},
   'user|u=s'       => \$os_opts{user},
   'sleep|s=i'      => \$run_opts{sleep_secs},
   'v+'             => \$mode  # -v -vv -vvv
    or exit 1;

$run_opts{background} ||= 1;

#
## initialize the thermostat
#
my $host = "10.0.1.173";
my $thermo_url = "http://$host/tstat";

my $ua = LWP::UserAgent->new;
my $req = HTTP::Request->new(GET => $thermo_url);

my $eci = 'cb68f5a0-a787-012f-49f0-00163ebcdddd';

my $event = Kinetic::Raise->new('thermostat',
			        'temperature',
				{'eci' => $eci}
			       );


#
## initialize the daemon activities
#

# From now on, all errors and warnings are also sent to syslog,
# provided by Log::Report. Output still also to the screen.
dispatcher SYSLOG => 'syslog', accept => 'INFO-'
  , identity => 'thermometer daemon', facility => 'local0';

dispatcher mode => $mode, 'ALL' if $mode;


my $daemon = Any::Daemon->new(%os_opts);

$daemon->run(child_task => \&run_task, %run_opts
	    );

exit 1;   # will never be called

sub run_task() {
  print "HEY THERE!\n";
    info "Starting temperature daemon";
    while(1) {   

      my $res = $ua->request($req);

      if ($res->is_success) {

	my $scalar = from_json($res->content);
	info "Temperature is " . $scalar->{ 'temp' } . "\n";

	my $response = $event->raise({'temperature' => $scalar->{ 'temp' },
				     }
				    );

	# foreach my $d (@{$response->{'directives'}}) {
	#   if ($d->{'name'} eq 'thermostat') {
	#     foreach my $o ($d->{'options'}) {
	#       info $o
	#     }
	#   }
	# }

      }

      sleep $run_opts{sleep_secs};
      
    }

    exit 0;
}

1;
