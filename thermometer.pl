#!/usr/bin/perl -w
# First, start the daemon.
#   ./thermometer.pl --user=<uid>


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
use YAML::XS;
use Data::Dumper;

use Kinetic::Raise;


use constant DEFAULT_CONFIG_FILE => 'config.yml';


#
## get command-line options
#

my $mode     = 0;     # increase output

my $config_filename;

my %os_opts  = ();

my %run_opts = ();

GetOptions
   'background|bg!' => \$run_opts{background},
   'group|g=s'      => \$os_opts{group},
   'pid-file|p=s'   => \$os_opts{pid_file},
   'user|u=s'       => \$os_opts{user},
   'config=s'       => \$config_filename,
   'v+'             => \$mode  # -v -vv -vvv
    or exit 1;

$run_opts{background} ||= 1;

#
## initialize the thermostat
#

my $config = read_config($config_filename || DEFAULT_CONFIG_FILE);

# print Dumper $config;

$run_opts{max_childs} ||= ($config->{max_children} || 1);
$os_opts{user} ||= $config->{user};
$os_opts{group} ||= $config->{group};
$os_opts{pid_file} ||= ($config->{pid_file} || '/tmp/thermometer.pid');

#
## initialize the daemon activities
#

# From now on, all errors and warnings are also sent to syslog,
# provided by Log::Report. Output still also to the screen.
dispatcher SYSLOG => 'syslog', accept => 'INFO-', identity => 'thermometer daemon', facility => 'local0';
dispatcher mode => $mode, 'ALL' if $mode;

my $daemon = Any::Daemon->new(%os_opts);

foreach my $k (keys %{ $config->{devices} }) {

  if ($config->{devices}->{$k}->{type} eq 'thermometer') {
    $daemon->run(child_task => &run_temperature_task($k, $config->{devices}->{$k}), 
		 %run_opts
		);
  } else {
    warning "No handler for device $k with type $config->{devices}->{$k}->{type}";
  }


}


exit 1;   # will never be called

#
# the task sub routines return a closure that has been properly configured. 
#

sub run_temperature_task(@) {
  my ($name, $config) = @_;

#  info Dumper $config;

  warning "No host name for termperature sensor $name" unless $config->{host};
  warning "No event channel identifier for termperature sensor $name" unless $config->{eci};

  my $thermo_url = "http://$config->{host}/tstat";

  my $ua = LWP::UserAgent->new;
  my $req = HTTP::Request->new(GET => $thermo_url);

  my $event = Kinetic::Raise->new('thermostat',
				  'temperature',
				  {'eci' => $config->{eci}}
				 );

  my $sleep_sec = $config->{sleep_secs} || 60;


  return sub {


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

      sleep $sleep_sec;
    }

    exit 0;
    
  }


}


sub read_config {
    my ($filename) = @_;
    my $config;
    if ( -e $filename ) {
      $config = YAML::XS::LoadFile($filename) ||
	warning "Can't open configuration file $filename: $!";
    }

    return $config;
}


1;
