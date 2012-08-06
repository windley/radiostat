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
#warn "Mode is $mode";

my $daemon;
$daemon = Any::Daemon->new(%os_opts);


foreach my $k (keys %{ $config->{devices} }) {

#  info "starting device $k";

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


    warning "Starting temperature daemon";

    while(1) {   

      my $res = $ua->request($req);

      if ($res->is_success) {

	my $scalar = from_json($res->content);
#	info "Temperature is " . $scalar->{ 'temp' } . "\n";
	warning "Temperature is " . $scalar->{ 'temp' } . "\n";

	my $response = $event->raise({'temperature' => $scalar->{ 'temp' },
				     }
				    );

#	warning Dumper $response->{'directives'};

	foreach my $d (@{$response->{'directives'}}) {
	   if ($d->{'name'} eq 'radstat') {
	     my $o = $d->{'options'};
	     if ($o->{'message'}) {
	       radstat_request($ua, "$thermo_url/pma", "message set", {message => $o->{'message'}} );
	     } elsif ($o->{'led'}) {
	       my $color = ($o->{'led'} eq "green")  ? 1 :
                           ($o->{'led'} eq "yellow") ? 2 :
                           ($o->{'led'} eq "red")    ? 4 :
                                                       0 ;   # off
	       radstat_request($ua, "$thermo_url/led", "LED color change ($color)" , {energy_led => $color});
	     }
	   }
	 }

      } else {
	warning "Can't connect to thermostat: " + $res->message;
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


#
# radstat functions
#

sub radstat_request {
  my ($ua, $resource_uri, $message, $content ) = @_;
  my $post = HTTP::Request->new(POST => $resource_uri);
  $post->content(to_json($content));
  my $res  = $ua->request($post);
  if ($res->is_success()) {
    parse_response($res, $message);
  } else {
    warning "HTTP request to $resource_uri failed: " . $res->message();
  }
  
}

sub parse_response {
  my($res, $message) = @_;
  my $content = from_json($res->content());
  if (defined $content->{'success'}) {
    warning "$message succeeded";
  } elsif (defined $content->{'error'}) {
    warning "$message failed";
  } else {
    warning "No status for $message";
    warning Dumper $res;
  }
}

1;
